package handlers

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
	"github.com/yehudahason/andromeda-forumV2/internal/auth"
	"github.com/yehudahason/andromeda-forumV2/internal/models"
)

func (h *Handler) GetForums(w http.ResponseWriter, r *http.Request) {
	forums := []models.Forum{}

	rows, err := h.DB.Query(
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
				ELSE COALESCE(p.name, 'Deleted user')
			END AS last_post_author,
			f.last_post_date
		FROM public.forums AS f
		LEFT JOIN public.profiles AS p
			ON p.id = f.last_post_author_id
		ORDER BY f.sort_order ASC, f.id ASC;
		`,
	)
	if err != nil {
		h.Logger.Error(
			"getForums query error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to get forums", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	for rows.Next() {
		var forum models.Forum

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
			h.Logger.Error(
				"getForums scan error",
				"error", err,
				"status", http.StatusInternalServerError,
			)

			http.Error(w, "Failed to scan forum", http.StatusInternalServerError)
			return
		}

		forums = append(forums, forum)
	}

	if err := rows.Err(); err != nil {
		h.Logger.Error(
			"getForums rows error",
			"error", err,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to read forums", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(forums); err != nil {
		h.Logger.Error(
			"getForums encode error",
			"error", err,
			"status", http.StatusOK,
		)
		return
	}
}

func (h *Handler) DeleteForum(w http.ResponseWriter, r *http.Request) {
	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
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
			"deleteForum authentication error",
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
		DELETE FROM public.forums
		WHERE id = $1
		`,
		forumID,
	)

	if err != nil {
		h.Logger.Error(
			"deleteForum database error",
			"error", err,
			"forum_id", forumID,
			"user_id", user.ID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to delete forum", http.StatusInternalServerError)
		return
	}

	if result.RowsAffected() == 0 {
		http.Error(w, "Forum not found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) CreateForum(w http.ResponseWriter, r *http.Request) {
	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"createForum authentication error",
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

	var input models.CreateForumRequest

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if input.SortOrder < 1 {
		http.Error(w, "Invalid sort order", http.StatusBadRequest)
		return
	}

	input.Name = strings.TrimSpace(input.Name)
	input.Description = strings.TrimSpace(input.Description)

	if input.Name == "" {
		http.Error(w, "Forum name is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Name) > 100 {
		http.Error(w, "Forum name is too long", http.StatusBadRequest)
		return
	}

	var forum models.Forum

	err = h.DB.QueryRow(
		r.Context(),
		`
		INSERT INTO public.forums (
			sort_order,
			name,
			description
		)
		VALUES ($1, $2, $3)
		RETURNING
			id,
			sort_order,
			name,
			description
		`,
		input.SortOrder,
		input.Name,
		input.Description,
	).Scan(
		&forum.ID,
		&forum.SortOrder,
		&forum.Name,
		&forum.Description,
	)

	if err != nil {
		h.Logger.Error(
			"failed to create forum",
			"error", err,
			"user_id", user.ID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to create forum", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)

	if err := json.NewEncoder(w).Encode(forum); err != nil {
		h.Logger.Error(
			"failed to encode forum",
			"error", err,
			"status", http.StatusCreated,
		)
	}
}

func (h *Handler) UpdateForum(w http.ResponseWriter, r *http.Request) {
	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"updateForum authentication error",
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

	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	var input models.CreateForumRequest

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if input.SortOrder < 1 {
		http.Error(w, "Invalid sort order", http.StatusBadRequest)
		return
	}

	input.Name = strings.TrimSpace(input.Name)
	input.Description = strings.TrimSpace(input.Description)

	if input.Name == "" {
		http.Error(w, "Forum name is required", http.StatusBadRequest)
		return
	}

	if utf8.RuneCountInString(input.Name) > 100 {
		http.Error(w, "Forum name is too long", http.StatusBadRequest)
		return
	}

	var forum models.Forum

	err = h.DB.QueryRow(
		r.Context(),
		`
		UPDATE public.forums
		SET
			name = $1,
			description = $2,
			sort_order = $3
		WHERE id = $4
		RETURNING
			id,
			sort_order,
			name,
			description
		`,
		input.Name,
		input.Description,
		input.SortOrder,
		forumID,
	).Scan(
		&forum.ID,
		&forum.SortOrder,
		&forum.Name,
		&forum.Description,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Forum not found", http.StatusNotFound)
			return
		}

		h.Logger.Error(
			"failed to update forum",
			"error", err,
			"forum_id", forumID,
			"user_id", user.ID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to update forum", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(forum); err != nil {
		h.Logger.Error(
			"failed to encode forum",
			"error", err,
			"status", http.StatusOK,
		)
	}
}
