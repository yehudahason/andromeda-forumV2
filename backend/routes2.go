package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5"
)

func getLatestPosts(w http.ResponseWriter, r *http.Request) {
	const perPage = 50

	page := 1

	if value := r.URL.Query().Get("page"); value != "" {
		n, err := strconv.Atoi(value)
		if err != nil || n < 1 {
			http.Error(w, "invalid page", http.StatusBadRequest)
			return
		}

		page = n
	}

	offset := (page - 1) * perPage

	const query = `
	SELECT
		posts.id,
		posts.post_type,
		posts.thread_id,
		posts.forum_id,
		f.name AS forum_name,

		posts.open_user_id,
		COALESCE(open_user.name, 'Deleted user') AS open_user_name,

		open_user.image AS open_user_image,

		posts.last_reply_user_id, COALESCE(last_reply_user.name, 'Deleted user') AS last_reply_user_name,

		posts.thread_title,
		posts.thread_content,
		posts.last_reply_content,
		posts.created_at,
		posts.messages_count

	FROM (
		SELECT *
		FROM (
			SELECT DISTINCT ON (r.thread_id)
				r.id::text AS id,
				'reply'::text AS post_type,
				r.thread_id,
				t.forum_id,

				t.user_id AS open_user_id,
				r.user_id AS last_reply_user_id,

				t.title AS thread_title,
				t.content AS thread_content,
				r.post AS last_reply_content,
				r.created_at,
				t.messages_count

			FROM replies r
			JOIN threads t
				ON t.id = r.thread_id

			ORDER BY
				r.thread_id,
				r.created_at DESC,
				r.id DESC
		) AS latest_replies

		UNION ALL

		SELECT
			t.id::text AS id,
			'thread'::text AS post_type,
			t.id AS thread_id,
			t.forum_id,

			t.user_id AS open_user_id,
			NULL::uuid AS last_reply_user_id,

			t.title AS thread_title,
			t.content AS thread_content,
			t.content AS content,
			t.created_at,
			t.messages_count

		FROM threads t

		WHERE NOT EXISTS (
			SELECT 1
			FROM replies r
			WHERE r.thread_id = t.id
		)
	) AS posts

	JOIN forums f
		ON f.id = posts.forum_id

	LEFT JOIN neon_auth."user" open_user
		ON open_user.id = posts.open_user_id

	LEFT JOIN neon_auth."user" last_reply_user
		ON last_reply_user.id = posts.last_reply_user_id

	ORDER BY posts.created_at DESC

	LIMIT $1
	OFFSET $2
`
	rows, err := db.Query(
		r.Context(),
		query,
		perPage,
		offset,
	)

	if err != nil {
		logger.Error(
			"failed to query latest posts",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(
			w,
			"failed to get latest posts",
			http.StatusInternalServerError,
		)
		return
	}
	defer rows.Close()

	posts := make([]LatestPost, 0, perPage)

	for rows.Next() {
		var post LatestPost
		if err := rows.Scan(
			&post.ID,
			&post.PostType,
			&post.ThreadID,
			&post.ForumID,
			&post.ForumName,

			&post.OpenUserID,
			&post.OpenUserName,
			&post.OpenUserImage,

			&post.LastReplyUserID,
			&post.LastReplyUserName,

			&post.ThreadTitle,
			&post.ThreadContent,
			&post.LastReplyContent,
			&post.CreatedAt,
			&post.MessagesCount,
		); err != nil {
			logger.Error(
				"failed to scan latest post",
				"error", err,
				"status", http.StatusInternalServerError,
			)

			http.Error(
				w,
				"failed to get latest posts",
				http.StatusInternalServerError,
			)
			return
		}

		posts = append(posts, post)
	}

	if err := rows.Err(); err != nil {
		logger.Error(
			"error iterating latest posts",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(
			w,
			"failed to get latest posts",
			http.StatusInternalServerError,
		)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(posts); err != nil {
		logger.Error(
			"failed to encode latest posts",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func getForumNameByID(
	ctx context.Context,
	forumID int64,
) (name string, found bool, err error) {
	const query = `
		SELECT name
		FROM forums
		WHERE id = $1
	`

	err = db.QueryRow(
		ctx,
		query,
		forumID,
	).Scan(&name)

	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}

	if err != nil {
		return "", false, err
	}

	return name, true, nil
}
