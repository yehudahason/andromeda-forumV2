package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/yehudahason/andromeda-forumV2/backend/internal/auth"
	"github.com/yehudahason/andromeda-forumV2/backend/internal/models"
)

type UserReply struct {
	ID          string    `json:"id"`
	Post        string    `json:"post"`
	ForumID     int64     `json:"forum_id"`
	ForumName   string    `json:"forum_name"`
	ThreadID    int64     `json:"thread_id"`
	ThreadTitle string    `json:"thread_title"`
	CreatedAt   time.Time `json:"created_at"`
	ThreadPage  int64     `json:"thread_page"`
}

type UserRepliesResponse struct {
	Replies    []UserReply `json:"replies"`
	Page       int         `json:"page"`
	TotalPages int64       `json:"total_pages"`
	Total      int64       `json:"total"`
	HasNext    bool        `json:"has_next"`
}

func (h *Handler) GetUserReplies(w http.ResponseWriter, r *http.Request) {
	const pageSize = 14

	userID := r.PathValue("id")

	var parsedID pgtype.UUID
	if err := parsedID.Scan(userID); err != nil {
		http.Error(w, "Invalid user ID", http.StatusBadRequest)
		return
	}

	page := 1

	if p := r.URL.Query().Get("page"); p != "" {
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 {
			http.Error(w, "Invalid page", http.StatusBadRequest)
			return
		}
		page = n
	}

	offset := (page - 1) * pageSize

	// Count user's replies
	var total int64

	err := h.DB.QueryRow(r.Context(), `
		SELECT COUNT(*)
		FROM public.replies
		WHERE user_id = $1
	`, parsedID).Scan(&total)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	// Fetch paginated replies
	rows, err := h.DB.Query(r.Context(), `
			SELECT
		    r.id::text,
	    	r.post,
	    	f.id,
    		f.name,
    		t.id,
    		t.title,

    		(
       		SELECT (COUNT(*) - 1) / 14 + 1
        	FROM public.replies AS r2
        	WHERE r2.thread_id = r.thread_id
    			AND (
        		(r2.created_at < r.created_at)
        		OR (
            	(r2.created_at = r.created_at)
            	AND (r2.id <= r.id)
       			 )
   			 )
			) AS thread_page,

    	 	r.created_at

			FROM public.replies AS r

			JOIN public.threads AS t
    		ON t.id = r.thread_id

			JOIN public.forums AS f
   		 	ON f.id = t.forum_id

			WHERE r.user_id = $1

			ORDER BY r.created_at DESC, r.id DESC

		LIMIT $2 OFFSET $3;
		`, parsedID, pageSize, offset)

	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	replies := make([]UserReply, 0)

	for rows.Next() {
		var reply UserReply

		err := rows.Scan(
			&reply.ID,
			&reply.Post,
			&reply.ForumID,
			&reply.ForumName,
			&reply.ThreadID,
			&reply.ThreadTitle,
			&reply.ThreadPage,
			&reply.CreatedAt,
		)

		if err != nil {
			http.Error(w, "Database error", http.StatusInternalServerError)
			return
		}

		replies = append(replies, reply)
	}

	if err := rows.Err(); err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	totalPages := (total + pageSize - 1) / pageSize

	response := UserRepliesResponse{
		Replies:    replies,
		Page:       page,
		TotalPages: totalPages,
		Total:      total,
		HasNext:    int64(page) < totalPages,
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(response); err != nil {
		return
	}
}

func (h *Handler) GetReplies(w http.ResponseWriter, r *http.Request) {
	const perPage = 14

	threadIDString := r.PathValue("threadID")

	threadID, err := strconv.ParseInt(threadIDString, 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	page := 1

	if pageString := r.URL.Query().Get("page"); pageString != "" {
		page, err = strconv.Atoi(pageString)
		if err != nil || page < 1 {
			http.Error(w, "Invalid page", http.StatusBadRequest)
			return
		}
	}

	// Make sure the thread exists.
	var threadTitle string

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT title
		FROM public.threads
		WHERE id = $1
		`,
		threadID,
	).Scan(&threadTitle)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Thread not found", http.StatusNotFound)
			return
		}

		http.Error(w, "Failed to get thread", http.StatusInternalServerError)
		return
	}

	var total int64

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT COUNT(*)
		FROM public.replies
		WHERE thread_id = $1
		`,
		threadID,
	).Scan(&total)

	if err != nil {
		http.Error(w, "Failed to count replies", http.StatusInternalServerError)
		return
	}

	offset := (page - 1) * perPage

	replies := []models.Reply{}

	rows, err := h.DB.Query(
		r.Context(),
		`
		SELECT
			r.id,
			r.thread_id,
			t.title,

			COALESCE(
				p.id,
				'00000000-0000-0000-0000-000000000000'::uuid
			) AS author_id,

			COALESCE(p.name, 'Deleted user') AS author_name,

			COALESCE(a.email, '') AS author_email,

			COALESCE(p.role, '') AS author_role,

			COALESCE(p.image_url, '') AS author_image,

			COALESCE(s.replies_count, 0) AS replies_count,

			p.created_at AS author_created_at,

			r.post,
			r.created_at,
			r.updated_at

		FROM public.replies AS r

		JOIN public.threads AS t
			ON t.id = r.thread_id

		LEFT JOIN public.profiles AS p
			ON p.id = r.user_id

		LEFT JOIN auth.users AS a
			ON a.id = p.auth_user_id

		LEFT JOIN public.forum_user_stats AS s
			ON s.user_id = p.auth_user_id

		WHERE r.thread_id = $1

		ORDER BY
			r.created_at ASC,
			r.id ASC

		LIMIT $2
		OFFSET $3
		`,
		threadID,
		perPage,
		offset,
	)
	if err != nil {
		h.Logger.Error(
			"getReplies query error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to get replies", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var reply models.Reply

		err := rows.Scan(
			&reply.ID,
			&reply.ThreadID,
			&reply.Title,
			&reply.Author.ID,
			&reply.Author.Name,
			&reply.Author.Email,
			&reply.Author.Role,
			&reply.Author.Image,
			&reply.Author.RepliesCount,
			&reply.Author.CreatedAt,
			&reply.Post,
			&reply.CreatedAt,
			&reply.UpdatedAt,
		)
		if err != nil {
			h.Logger.Error(
				"getReplies scan error",
				"error", err,
				"status", http.StatusInternalServerError,
			)

			http.Error(w, "Failed to scan reply", http.StatusInternalServerError)
			return
		}

		replies = append(replies, reply)
	}

	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to read replies", http.StatusInternalServerError)
		return
	}

	response := models.ReplyListResponse{
		Replies: replies,
		Total:   total,
		Page:    page,
		PerPage: perPage,
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(response); err != nil {
		h.Logger.Error(
			"getReplies encode error",
			"error", err,
			"status", http.StatusOK,
		)
		return
	}
}

func (h *Handler) UpdateReply(w http.ResponseWriter, r *http.Request) {
	replyIDString := r.PathValue("replyID")

	replyID, err := uuid.Parse(replyIDString)
	if err != nil {
		http.Error(w, "Invalid reply ID", http.StatusBadRequest)
		return
	}

	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"updateReply authentication error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var input struct {
		Post   string `json:"post"`
		Notify bool   `json:"notify"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	input.Post = strings.TrimSpace(input.Post)

	if input.Post == "" {
		http.Error(w, "Post is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Post) > 100000 {
		http.Error(w, "Post is too long", http.StatusBadRequest)
		return
	}

	var reply struct {
		ID       uuid.UUID `json:"id"`
		Post     string    `json:"post"`
		Notify   bool      `json:"notify"`
		ThreadID int64     `json:"thread_id"`
	}

	err = h.DB.QueryRow(
		r.Context(),
		`
	WITH updated_reply AS (
		UPDATE public.replies
		SET
			post = $1,
			notify = $2
		WHERE id = $3
		  AND user_id = $4
		RETURNING
			id,
			thread_id,
			post,
			notify
	),
	mark_read AS (
		INSERT INTO public.thread_reads (
			user_id,
			thread_id,
			last_read_at
		)
		SELECT
			$4,
			thread_id,
			now()
		FROM updated_reply
		ON CONFLICT (user_id, thread_id)
		DO UPDATE SET
			last_read_at = EXCLUDED.last_read_at
	)
	SELECT
		id,
		thread_id,
		post,
		notify
	FROM updated_reply
	`,
		input.Post,
		input.Notify,
		replyID,
		user.ID,
	).Scan(
		&reply.ID,
		&reply.ThreadID,
		&reply.Post,
		&reply.Notify,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Reply not found or not allowed", http.StatusNotFound)
			return
		}

		h.Logger.Error(
			"updateReply database error",
			"error", err,
			"reply_id", replyID,
			"user_id", user.ID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to update reply", http.StatusInternalServerError)
		return
	}

	if input.Notify {
		err = h.FollowThread(r.Context(), user.ID, reply.ThreadID)
	} else {
		err = h.UnfollowThread(r.Context(), user.ID, reply.ThreadID)
	}

	if err != nil {
		h.Logger.Error(
			"Failed to follow thread",
			"error", err,
			"thread_id", reply.ThreadID,
			"user_id", user.ID,
		)
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(reply); err != nil {
		h.Logger.Error(
			"updateReply encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func (h *Handler) GetReplyPositionHandler(w http.ResponseWriter, r *http.Request) {
	threadIDString := r.PathValue("threadID")
	replyIDString := r.PathValue("replyID")

	threadID, err := strconv.ParseInt(threadIDString, 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	replyID, err := uuid.Parse(replyIDString)
	if err != nil {
		http.Error(w, "Invalid reply ID", http.StatusBadRequest)
		return
	}

	position, err := h.getReplyPosition(
		r.Context(),
		threadID,
		replyID,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Reply not found", http.StatusNotFound)
			return
		}

		h.Logger.Error(
			"failed to get reply position",
			"thread_id", threadID,
			"reply_id", replyID,
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(map[string]int64{
		"position": position,
	}); err != nil {
		h.Logger.Error(
			"getReplyPosition encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func (h *Handler) getReplyPosition(
	ctx context.Context,
	threadID int64,
	replyID uuid.UUID,
) (int64, error) {

	const query = `
		SELECT position
		FROM (
			SELECT
				id,
				ROW_NUMBER() OVER (
					ORDER BY created_at ASC, id ASC
				) AS position
			FROM public.replies
			WHERE thread_id = $1
		) AS r
		WHERE id = $2
	`

	var position int64

	err := h.DB.QueryRow(
		ctx,
		query,
		threadID,
		replyID,
	).Scan(&position)

	if err != nil {
		return 0, err
	}

	return position, nil
}

func (h *Handler) GetReplyByID(w http.ResponseWriter, r *http.Request) {
	replyIDString := r.PathValue("replyID")

	replyID, err := uuid.Parse(replyIDString)
	if err != nil {
		http.Error(w, "Invalid reply ID", http.StatusBadRequest)
		return
	}

	var reply models.ReplyPost

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT
			id,
			post,
			notify
		FROM public.replies
		WHERE id = $1
		`,
		replyID,
	).Scan(
		&reply.ID,
		&reply.Post,
		&reply.Notify,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Reply not found", http.StatusNotFound)
			return
		}

		h.Logger.Error(
			"failed to get reply",
			"reply_id", replyID,
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(reply); err != nil {
		h.Logger.Error(
			"failed to encode reply",
			"reply_id", replyID,
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func (h *Handler) CreateReply(w http.ResponseWriter, r *http.Request) {
	forumIDString := r.PathValue("forumID")
	threadIDString := r.PathValue("threadID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	threadID, err := strconv.ParseInt(threadIDString, 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			h.Logger.Warn(
				"createReply authentication failed",
				"error", err,
				"status", http.StatusUnauthorized,
			)

			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"createReply authentication database error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var input models.CreateReplyRequest

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	input.Post = strings.TrimSpace(input.Post)

	if input.Post == "" {
		http.Error(w, "Post is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Post) > 100000 {
		http.Error(w, "Post is too long", http.StatusBadRequest)
		return
	}

	// Make sure the thread exists and belongs to this forum.
	var exists bool

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT EXISTS (
			SELECT 1
			FROM public.threads
			WHERE id = $1
			  AND forum_id = $2
		)
		`,
		threadID,
		forumID,
	).Scan(&exists)

	if err != nil {
		h.Logger.Error(
			"createReply failed to check thread",
			"error", err,
			"thread_id", threadID,
			"forum_id", forumID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to check thread", http.StatusInternalServerError)
		return
	}

	if !exists {
		http.Error(w, "Thread not found", http.StatusNotFound)
		return
	}

	var reply models.CreateReplyResponse

	err = h.DB.QueryRow(
		r.Context(),
		`
	WITH new_reply AS (
		INSERT INTO public.replies (
			thread_id,
			user_id,
			post,
			notify
		)
		VALUES ($1, $2, $3, $4)
		RETURNING
			id,
			thread_id,
			user_id,
			post,
			notify,
			created_at
	),
	mark_read AS (
		INSERT INTO public.thread_reads (
			user_id,
			thread_id,
			last_read_at
		)
		SELECT
			user_id,
			thread_id,
			created_at
		FROM new_reply
		ON CONFLICT (user_id, thread_id)
		DO UPDATE SET
			last_read_at = EXCLUDED.last_read_at
	)
	SELECT
		id,
		thread_id,
		user_id,
		post,
		notify,
		created_at
	FROM new_reply
	`,
		threadID,
		user.ID,
		input.Post,
		input.Notify,
	).Scan(
		&reply.ID,
		&reply.ThreadID,
		&reply.UserID,
		&reply.Post,
		&reply.Notify,
		&reply.CreatedAt,
	)

	if err != nil {
		h.Logger.Error(
			"createReply insert error",
			"error", err,
			"user_id", user.ID,
			"thread_id", threadID,
			"forum_id", forumID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to create reply", http.StatusInternalServerError)
		return
	}

	if input.Notify {
		err = h.FollowThread(
			r.Context(),
			user.ID,
			threadID,
		)

		if err != nil {
			h.Logger.Error(
				"Failed to follow thread",
				"error", err,
				"thread_id", threadID,
			)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)

	if err := json.NewEncoder(w).Encode(reply); err != nil {
		h.Logger.Error(
			"createReply encode error",
			"error", err,
			"status", http.StatusCreated,
		)
	}
}

func (h *Handler) DeleteReply(w http.ResponseWriter, r *http.Request) {
	replyIDString := r.PathValue("replyID")

	replyID, err := uuid.Parse(replyIDString)
	if err != nil {
		http.Error(w, "Invalid reply ID", http.StatusBadRequest)
		return
	}

	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"deleteReply authentication error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	if user.Role != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	result, err := h.DB.Exec(
		r.Context(),
		`
		DELETE FROM public.replies
		WHERE id = $1
		`,
		replyID,
	)

	if err != nil {
		h.Logger.Error(
			"deleteReply database error",
			"error", err,
			"reply_id", replyID,
			"user_id", user.ID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to delete reply", http.StatusInternalServerError)
		return
	}

	if result.RowsAffected() == 0 {
		http.Error(w, "Reply not found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
