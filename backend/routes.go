package main

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
)

func getForums(w http.ResponseWriter, r *http.Request) {
	forums := []Forum{}

	rows, err := db.Query(
		r.Context(),
		`
		SELECT
			f.id,
			f.name,
			f.description,
			f.messages_count,
			f.last_post_thread_id,
			f.last_post_title,
			f.sort_order,
			CASE
				WHEN f.last_post_date IS NULL THEN NULL
				ELSE COALESCE(u.name, 'Deleted user')
			END AS last_post_author,
			f.last_post_date
		FROM forums AS f
		LEFT JOIN neon_auth."user" AS u
			ON u.id = f.last_post_author_id
		ORDER BY f.sort_order ASC, f.id ASC;
		`,
	)
	if err != nil {
		fmt.Print(err)
		http.Error(w, "Failed to get forums", http.StatusInternalServerError)

		return
	}
	defer rows.Close()

	for rows.Next() {
		var forum Forum

		err := rows.Scan(
			&forum.ID,
			&forum.Name,
			&forum.Description,
			&forum.MessagesCount,
			&forum.LastPostThreadId,
			&forum.LastPostTitle,
			&forum.SortOrder,
			&forum.LastPostAuthor,
			&forum.LastPostDate,
		)
		if err != nil {
			fmt.Print(err)
			http.Error(w, "Failed to scan forum", http.StatusInternalServerError)
			return
		}

		forums = append(forums, forum)
	}

	if err := rows.Err(); err != nil {
		fmt.Print(err)
		http.Error(w, "Failed to read forums", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(forums); err != nil {
		logger.Error(
			"getForums encode error",
			"error", err,
			"status", http.StatusOK,
		)
		return
	}
}

func getThreads(w http.ResponseWriter, r *http.Request) {
	const perPage = 14

	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	var forumName string

	err = db.QueryRow(
		r.Context(),
		`
	SELECT name
	FROM forums
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

	err = db.QueryRow(
		r.Context(),
		`
		SELECT COUNT(*)
		FROM threads
		WHERE forum_id = $1
		`,
		forumID,
	).Scan(&total)

	if err != nil {
		http.Error(w, "Failed to count threads", http.StatusInternalServerError)
		return
	}

	threads := []Thread{}

	rows, err := db.Query(
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
			t.created_at
		FROM threads AS t

		LEFT JOIN neon_auth."user" AS u
			ON u.id = t.user_id

		LEFT JOIN neon_auth."user" AS lp
			ON lp.id = t.last_post_author_id

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
	)
	if err != nil {
		http.Error(w, "Failed to get threads", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var thread Thread

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

	response := ThreadListResponse{
		Threads:   threads,
		Total:     total,
		Page:      page,
		PerPage:   perPage,
		ForumName: forumName,
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(response); err != nil {
		logger.Error(
			"getThreads encode error",
			"error", err,
			"status", http.StatusOK,
		)
		return
	}
}

func getReplies(w http.ResponseWriter, r *http.Request) {
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

	err = db.QueryRow(
		r.Context(),
		`
		SELECT title
		FROM threads
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

	err = db.QueryRow(
		r.Context(),
		`
		SELECT COUNT(*)
		FROM replies
		WHERE thread_id = $1
		`,
		threadID,
	).Scan(&total)

	if err != nil {
		http.Error(w, "Failed to count replies", http.StatusInternalServerError)
		return
	}

	offset := (page - 1) * perPage

	replies := []Reply{}

	rows, err := db.Query(
		r.Context(),
		`
		SELECT
			r.id,
			r.thread_id,
			t.title,
			COALESCE(u.id, '00000000-0000-0000-0000-000000000000'::uuid),
			COALESCE(u.name, 'Deleted user'),
			COALESCE(u.email, ''),
			COALESCE(u.role, ''),
			COALESCE(u.image, ''),
			COALESCE(u.replies_count, 0),
			u."createdAt",

			r.post,
			r.created_at,
			r.updated_at
		FROM replies AS r

		JOIN threads AS t
			ON t.id = r.thread_id

		LEFT JOIN neon_auth."user" AS u
			ON u.id = r.user_id

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
		logger.Error(
			"failed to scan reply",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to scan reply", http.StatusInternalServerError)
		return
	}
	// if err != nil {
	// 	http.Error(w, "Failed to get replies", http.StatusInternalServerError)
	// 	return
	// }
	defer rows.Close()

	for rows.Next() {
		var reply Reply

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
			http.Error(w, "Failed to scan reply", http.StatusInternalServerError)
			return
		}

		replies = append(replies, reply)
	}

	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to read replies", http.StatusInternalServerError)
		return
	}

	response := ReplyListResponse{
		Replies: replies,
		Total:   total,
		Page:    page,
		PerPage: perPage,
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(response); err != nil {
		logger.Error(
			"getReplies encode error",
			"error", err,
			"status", http.StatusOK,
		)
		return
	}
}

func createThread(w http.ResponseWriter, r *http.Request) {
	// Get forum ID from:
	// POST /forums/{forumID}/threads
	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	// Get logged-in user before checking whether the forum exists.
	// This keeps protected POST routes consistent and avoids exposing
	// resource existence to unauthenticated callers.
	user, err := getUserID(r)
	if err != nil {
		if errors.Is(err, ErrUnauthorized) {
			logger.Warn(
				"createThread authentication failed",
				"error", err,
				"status", http.StatusUnauthorized,
			)

			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		logger.Error(
			"createThread authentication database error",
			"error", err,
			"status", http.StatusInternalServerError,
		)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var forumExists bool

	err = db.QueryRow(
		r.Context(),
		`
		SELECT EXISTS (
			SELECT 1
			FROM forums
			WHERE id = $1
		)
		`,
		forumID,
	).Scan(&forumExists)

	if err != nil {
		http.Error(w, "Failed to check forum", http.StatusInternalServerError)
		return
	}

	if !forumExists {
		http.Error(w, "Forum not found", http.StatusNotFound)
		return
	}
	var input CreateThreadRequest

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

	var thread CreateThreadResponse

	err = db.QueryRow(
		r.Context(),
		`
		INSERT INTO threads (
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
			title,
			content,
			notify,
			created_at
		`,
		forumID,
		user.ID,
		input.Title,
		input.Content,
		input.Notify,
	).Scan(
		&thread.ID,
		&thread.ForumID,
		&thread.Title,
		&thread.Content,
		&thread.Notify,
		&thread.CreatedAt,
	)

	if err != nil {
		http.Error(w, "Failed to create thread", http.StatusInternalServerError)
		return
	}

	thread.UserID = user.ID.String()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)

	if err := json.NewEncoder(w).Encode(thread); err != nil {
		logger.Error(
			"createThread encode error",
			"error", err,
			"status", http.StatusCreated,
		)
		return
	}
}

func updateThread(w http.ResponseWriter, r *http.Request) {
	threadIDString := r.PathValue("threadID")

	threadID, err := strconv.ParseInt(threadIDString, 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	user, err := getUserID(r)
	if err != nil {
		if errors.Is(err, ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		logger.Error(
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

	err = db.QueryRow(
		r.Context(),
		`
		UPDATE threads
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

		logger.Error(
			"updateThread database error",
			"error", err,
			"status", http.StatusInternalServerError,
		)
		http.Error(w, "Failed to update thread", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(thread); err != nil {
		logger.Error(
			"updateThread encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func updateReply(w http.ResponseWriter, r *http.Request) {
	replyID := r.PathValue("replyID")

	user, err := getUserID(r)
	if err != nil {
		if errors.Is(err, ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		logger.Error(
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
		ID     uuid.UUID `json:"id"`
		Post   string    `json:"post"`
		Notify bool      `json:"notify"`
	}

	err = db.QueryRow(
		r.Context(),
		`
		UPDATE replies
		SET
			post = $1,
			notify = $2
		WHERE id = $3
		  AND user_id = $4
		RETURNING
			id,
			post,
			notify
		`,
		input.Post,
		input.Notify,
		replyID,
		user.ID,
	).Scan(
		&reply.ID,
		&reply.Post,
		&reply.Notify,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Reply not found or not allowed", http.StatusNotFound)
			return
		}

		logger.Error(
			"updateReply database error",
			"error", err,
			"status", http.StatusInternalServerError,
		)
		http.Error(w, "Failed to update reply", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(reply); err != nil {
		logger.Error(
			"updateReply encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func getReplyPositionHandler(w http.ResponseWriter, r *http.Request) {
	threadIDStr := r.PathValue("threadID")
	replyID := r.PathValue("replyID")

	threadID, err := strconv.ParseInt(threadIDStr, 10, 64)
	if err != nil {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	if replyID == "" {
		http.Error(w, "Reply ID is missing", http.StatusBadRequest)
		return
	}

	position, err := getReplyPosition(
		r.Context(),
		threadID,
		replyID,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Reply not found", http.StatusNotFound)
			return
		}

		logger.Error("failed to get reply position",
			"thread_id", threadID,
			"reply_id", replyID,
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	json.NewEncoder(w).Encode(map[string]int64{
		"position": position,
	})
}
func getReplyPosition(
	ctx context.Context,
	threadID int64,
	replyID string,
) (int64, error) {

	const query = `
		SELECT position
		FROM (
			SELECT
				id,
				ROW_NUMBER() OVER (
					ORDER BY created_at ASC, id ASC
				) AS position
			FROM replies
			WHERE thread_id = $1
		) r
		WHERE id = $2;
	`

	var position int64

	err := db.QueryRow(
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

func getReplyByID(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("replyID")

	if id == "" {
		http.Error(w, "Reply ID is required", http.StatusBadRequest)
		return
	}

	var reply ReplyPost

	err := db.QueryRow(
		r.Context(),
		`
		SELECT
			id,
			post,
			notify
		FROM replies
		WHERE id = $1
		`,
		id,
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

		logger.Error("failed to get reply",
			"reply_id", id,
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(reply); err != nil {
		logger.Error("failed to encode reply",
			"reply_id", id,
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func getThreadByID(w http.ResponseWriter, r *http.Request) {
	var forumID int64

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

	var thread ThreadDetails
	const query = `
		SELECT
			t.id,
			f.name,
			t.forum_id,

			COALESCE(
				u.id,
				'00000000-0000-0000-0000-000000000000'::uuid
			),
			COALESCE(u.role, ''),
			COALESCE(u.name, 'Deleted user'),
			COALESCE(u.email, ''),
			COALESCE(u.image, ''),
			COALESCE(u.replies_count, 0),
			u."createdAt",

			t.title,
			t.content,
			t.created_at

		FROM threads AS t

		JOIN forums AS f
			ON f.id = t.forum_id

		LEFT JOIN neon_auth."user" AS u
			ON u.id = t.user_id

		WHERE t.id = $1
		`

	err = db.QueryRow(
		r.Context(),
		query,
		threadID,
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

		logger.Error(
			"getThreadByID query error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to get thread", http.StatusInternalServerError)
		return
	}

	if forumID != thread.ForumID {
		http.Error(w, "Thread not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(thread); err != nil {
		logger.Error(
			"getThreadByID encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}
func createReply(w http.ResponseWriter, r *http.Request) {
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

	user, err := getUserID(r)
	if err != nil {
		if errors.Is(err, ErrUnauthorized) {
			logger.Warn(
				"createReply authentication failed",
				"error", err,
				"status", http.StatusUnauthorized,
			)

			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		logger.Error(
			"createReply authentication database error",
			"error", err,
			"status", http.StatusInternalServerError,
		)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	var input CreateReplyRequest

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

	// Make sure thread exists and belongs to this forum.
	var exists bool

	err = db.QueryRow(
		r.Context(),
		`
		SELECT EXISTS (
			SELECT 1
			FROM threads
			WHERE id = $1
			  AND forum_id = $2
		)
		`,
		threadID,
		forumID,
	).Scan(&exists)

	if err != nil {
		http.Error(w, "Failed to check thread", http.StatusInternalServerError)
		return
	}

	if !exists {
		http.Error(w, "Thread not found", http.StatusNotFound)
		return
	}

	var reply CreateReplyResponse

	err = db.QueryRow(
		r.Context(),
		`
		INSERT INTO replies (
			thread_id,
			user_id,
			post,
			notify
		)
		VALUES ($1, $2, $3, $4)
		RETURNING
			id,
			thread_id,
			post,
			notify,
			created_at
		`,
		threadID,
		user.ID,
		input.Post,
		input.Notify,
	).Scan(
		&reply.ID,
		&reply.ThreadID,
		&reply.Post,
		&reply.Notify,
		&reply.CreatedAt,
	)

	if err != nil {
		logger.Error(
			"createReply INSERT error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(
			w,
			"Failed to create reply",
			http.StatusInternalServerError,
		)
		return
	}

	reply.UserID = user.ID.String()

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)

	if err := json.NewEncoder(w).Encode(reply); err != nil {
		logger.Error(
			"createReply encode error",
			"error", err,
			"status", http.StatusCreated,
		)
		return
	}
}
