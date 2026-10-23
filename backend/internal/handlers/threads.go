package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/yehudahason/andromeda-forumV2/backend/internal/auth"
	"github.com/yehudahason/andromeda-forumV2/backend/internal/models"
)

func (h *Handler) GetThreads(w http.ResponseWriter, r *http.Request) {

	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"getThreads authentication error",
			"error", err,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}
	const perPage = 14

	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	var forumName string

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT name
		FROM public.forums
		WHERE id = $1
		`,
		forumID,
	).Scan(&forumName)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Forum not found", http.StatusNotFound)
			return
		}

		http.Error(w, "Failed to get forum", http.StatusInternalServerError)
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

	offset := (page - 1) * perPage

	var total int64

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT COUNT(*)
		FROM public.threads
		WHERE forum_id = $1
		`,
		forumID,
	).Scan(&total)

	if err != nil {
		http.Error(w, "Failed to count threads", http.StatusInternalServerError)
		return
	}

	threads := []models.Thread{}

	rows, err := h.DB.Query(
		r.Context(),
		`
	SELECT
		t.id,
		t.forum_id,
		t.title,
		COALESCE(u.name, 'Deleted user') AS author,
		t.messages_count,
		t.last_post_title,
		COALESCE(lp.name, 'Deleted user') AS last_post_author,
		t.last_post_date,
		t.created_at,
		t.views,

		CASE
			WHEN tr.last_read_at IS NULL THEN TRUE
			WHEN t.last_post_date > tr.last_read_at THEN TRUE
			ELSE FALSE
		END AS unread

	FROM public.threads AS t

	LEFT JOIN public.profiles AS u
		ON u.id = t.user_id

	LEFT JOIN public.profiles AS lp
		ON lp.id = t.last_post_author_id

	LEFT JOIN public.thread_reads AS tr
		ON tr.thread_id = t.id
		AND tr.user_id = $4

	WHERE t.forum_id = $1

	ORDER BY
		t.sticky DESC,
		t.last_post_date DESC,
		t.id DESC

	LIMIT $2
	OFFSET $3
	`,
		forumID,
		perPage,
		offset,
		user.ID,
	)
	if err != nil {
		http.Error(w, "Failed to get threads", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var thread models.Thread

		err := rows.Scan(
			&thread.ID,
			&thread.ForumID,
			&thread.Title,
			&thread.Author,
			&thread.MessagesCount,
			&thread.LastPostTitle,
			&thread.LastPostAuthor,
			&thread.LastPostDate,
			&thread.CreatedAt,
			&thread.Views,
			&thread.Unread,
		)
		if err != nil {
			http.Error(w, "Failed to scan thread", http.StatusInternalServerError)
			return
		}

		threads = append(threads, thread)
	}

	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to read threads", http.StatusInternalServerError)
		return
	}

	response := models.ThreadListResponse{
		Threads:   threads,
		Total:     total,
		Page:      page,
		PerPage:   perPage,
		ForumName: forumName,
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(response); err != nil {
		h.Logger.Error(
			"getThreads encode error",
			"error", err,
			"status", http.StatusOK,
		)
		return
	}
}

func (h *Handler) CreateThread(w http.ResponseWriter, r *http.Request) {
	// POST /forums/{forumID}/threads
	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	// Authenticate user.
	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			h.Logger.Warn(
				"createThread authentication failed",
				"error", err,
				"status", http.StatusUnauthorized,
			)

			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"createThread authentication database error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Make sure forum exists.
	var forumExists bool

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT EXISTS (
			SELECT 1
			FROM public.forums
			WHERE id = $1
		)
		`,
		forumID,
	).Scan(&forumExists)

	if err != nil {
		h.Logger.Error(
			"createThread failed to check forum",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to check forum", http.StatusInternalServerError)
		return
	}

	if !forumExists {
		http.Error(w, "Forum not found", http.StatusNotFound)
		return
	}

	var input models.CreateThreadRequest

	err = json.NewDecoder(r.Body).Decode(&input)
	if err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	input.Title = strings.TrimSpace(input.Title)
	input.Content = strings.TrimSpace(input.Content)

	if input.Title == "" {
		http.Error(w, "Title is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Title) > 255 {
		http.Error(w, "Title is too long", http.StatusBadRequest)
		return
	}

	if input.Content == "" {
		http.Error(w, "Content is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Content) > 100000 {
		http.Error(w, "Content is too long", http.StatusBadRequest)
		return
	}

	var thread models.CreateThreadResponse

	err = h.DB.QueryRow(
		r.Context(),
		`
	WITH new_thread AS (
		INSERT INTO public.threads (
			forum_id,
			user_id,
			title,
			content,
			notify
		)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING
			id,
			forum_id,
			user_id,
			title,
			content,
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
			$2,
			id,
			now()
		FROM new_thread
		ON CONFLICT (user_id, thread_id)
		DO UPDATE SET
			last_read_at = EXCLUDED.last_read_at
	)
	SELECT
		id,
		forum_id,
		user_id,
		title,
		content,
		notify,
		created_at
	FROM new_thread
	`,
		forumID,
		user.ID,
		input.Title,
		input.Content,
		input.Notify,
	).Scan(
		&thread.ID,
		&thread.ForumID,
		&thread.UserID,
		&thread.Title,
		&thread.Content,
		&thread.Notify,
		&thread.CreatedAt,
	)

	if err != nil {
		h.Logger.Error(
			"createThread insert error",
			"error", err,
			"user_id", user.ID,
			"forum_id", forumID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to create thread", http.StatusInternalServerError)
		return
	}
	if input.Notify {

		id, err := uuid.Parse(thread.UserID)
		if err != nil {
			fmt.Println("Invalid UUID:", err)
			return
		}
		err = h.FollowThread(
			r.Context(),
			id,
			thread.ID,
		)

		if err != nil {
			h.Logger.Error(
				"Failed to follow thread",
				"error", err,
				"thread_id", thread.ID,
			)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)

	if err := json.NewEncoder(w).Encode(thread); err != nil {
		h.Logger.Error(
			"createThread encode error",
			"error", err,
			"status", http.StatusCreated,
		)
	}
}

func (h *Handler) UpdateThread(w http.ResponseWriter, r *http.Request) {
	threadIDString := r.PathValue("threadID")

	threadID, err := strconv.ParseInt(threadIDString, 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
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
			"updateThread authentication error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var input struct {
		Title   string `json:"title"`
		Content string `json:"content"`
		Notify  bool   `json:"notify"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	input.Title = strings.TrimSpace(input.Title)
	input.Content = strings.TrimSpace(input.Content)

	if input.Title == "" {
		http.Error(w, "Title is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Title) > 255 {
		http.Error(w, "Title is too long", http.StatusBadRequest)
		return
	}

	if input.Content == "" {
		http.Error(w, "Content is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Content) > 100000 {
		http.Error(w, "Content is too long", http.StatusBadRequest)
		return
	}

	var thread struct {
		ID      int64  `json:"id"`
		Title   string `json:"title"`
		Content string `json:"content"`
		Notify  bool   `json:"notify"`
	}

	err = h.DB.QueryRow(
		r.Context(),
		`
	WITH updated_thread AS (
		UPDATE public.threads
		SET
			title = $1,
			content = $2,
			notify = $3
		WHERE id = $4
		  AND user_id = $5
		RETURNING
			id,
			title,
			content,
			notify
	),
	mark_read AS (
		INSERT INTO public.thread_reads (
			user_id,
			thread_id,
			last_read_at
		)
		SELECT
			$5,
			id,
			now()
		FROM updated_thread
		ON CONFLICT (user_id, thread_id)
		DO UPDATE SET
			last_read_at = EXCLUDED.last_read_at
	)
	SELECT
		id,
		title,
		content,
		notify
	FROM updated_thread
	`,
		input.Title,
		input.Content,
		input.Notify,
		threadID,
		user.ID,
	).Scan(
		&thread.ID,
		&thread.Title,
		&thread.Content,
		&thread.Notify,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Thread not found or not allowed", http.StatusNotFound)
			return
		}

		h.Logger.Error(
			"updateThread database error",
			"error", err,
			"thread_id", threadID,
			"user_id", user.ID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to update thread", http.StatusInternalServerError)
		return
	}

	if input.Notify {

		err = h.FollowThread(r.Context(), user.ID, thread.ID)
	} else {
		err = h.UnfollowThread(r.Context(), user.ID, thread.ID)
	}
	if err != nil {
		h.Logger.Error(
			"Failed to follow thread",
			"error", err,
			"thread_id", thread.ID,
		)
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(thread); err != nil {
		h.Logger.Error(
			"updateThread encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func (h *Handler) GetThreadByID(w http.ResponseWriter, r *http.Request) {
	forumString := r.URL.Query().Get("f")
	if forumString == "" {
		http.Error(w, "Missing forum ID", http.StatusBadRequest)
		return
	}

	forumID, err := strconv.ParseInt(forumString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	threadIDString := r.PathValue("threadID")

	threadID, err := strconv.ParseInt(threadIDString, 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	err = h.incrementThreadViews(r.Context(), threadID)
	if err != nil {
		h.Logger.Error("failed to increment thread views",
			"thread_id", threadID,
			"error", err,
		)
	}

	var thread models.ThreadDetails

	const query = `
		SELECT
			t.id,
			f.name,
			t.forum_id,

			COALESCE(
				p.id,
				'00000000-0000-0000-0000-000000000000'::uuid
			) AS author_id,

			COALESCE(a.role, '') AS author_role,
			COALESCE(p.name, 'Deleted user') AS author_name,
			COALESCE(a.email, '') AS author_email,
			COALESCE(p.image_url, '') AS author_image,
			COALESCE(s.replies_count, 0) AS author_replies_count,
			p.created_at AS author_created_at,

			t.title,
			t.content,
			t.created_at

		FROM public.threads AS t

		JOIN public.forums AS f
			ON f.id = t.forum_id

		LEFT JOIN public.profiles AS p
			ON p.id = t.user_id

		LEFT JOIN auth.users AS a
			ON a.id = p.auth_user_id

		LEFT JOIN public.forum_user_stats AS s
			ON s.user_id = p.auth_user_id

		WHERE t.id = $1
		  AND t.forum_id = $2
	`

	err = h.DB.QueryRow(
		r.Context(),
		query,
		threadID,
		forumID,
	).Scan(
		&thread.ID,
		&thread.ForumName,
		&thread.ForumID,

		&thread.Author.ID,
		&thread.Author.Role,
		&thread.Author.Name,
		&thread.Author.Email,
		&thread.Author.Image,
		&thread.Author.RepliesCount,
		&thread.Author.CreatedAt,

		&thread.Title,
		&thread.Content,
		&thread.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Thread not found", http.StatusNotFound)
			return
		}

		h.Logger.Error(
			"getThreadByID query error",
			"thread_id", threadID,
			"forum_id", forumID,
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to get thread", http.StatusInternalServerError)
		return
	}

	user, err := h.Auth.GetUser(r)

	if err == nil {
		_, err = h.DB.Exec(
			r.Context(),
			`
		INSERT INTO public.thread_reads (
			user_id,
			thread_id,
			last_read_at
		)
		VALUES ($1, $2, now())
		ON CONFLICT (user_id, thread_id)
		DO UPDATE SET
			last_read_at = EXCLUDED.last_read_at
		`,
			user.ID,
			threadID,
		)

		if err != nil {
			h.Logger.Error(
				"failed to mark thread as read",
				"error", err,
				"user_id", user.ID,
				"thread_id", threadID,
			)
		}
	}
	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(thread); err != nil {
		h.Logger.Error(
			"getThreadByID encode error",
			"thread_id", threadID,
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func (h *Handler) incrementThreadViews(ctx context.Context, threadID int64) error {
	_, err := h.DB.Exec(
		ctx,
		`
		UPDATE threads
		SET views = views + 1
		WHERE id = $1
		`,
		threadID,
	)

	if err != nil {
		return fmt.Errorf("increment thread views: %w", err)
	}

	return nil
}
