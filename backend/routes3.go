package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

func deleteForum(w http.ResponseWriter, r *http.Request) {
	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
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

	result, err := db.Exec(
		r.Context(),
		`
		DELETE FROM public.forums
		WHERE id = $1
		`,
		forumID,
	)

	if err != nil {
		logger.Error(
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

func deleteThread(w http.ResponseWriter, r *http.Request) {
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
			"deleteThread authentication error",
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

	result, err := db.Exec(
		r.Context(),
		`
		DELETE FROM public.threads
		WHERE id = $1
		`,
		threadID,
	)

	if err != nil {
		logger.Error(
			"deleteThread database error",
			"error", err,
			"thread_id", threadID,
			"user_id", user.ID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Failed to delete thread", http.StatusInternalServerError)
		return
	}

	if result.RowsAffected() == 0 {
		http.Error(w, "Thread not found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func deleteReply(w http.ResponseWriter, r *http.Request) {
	replyIDString := r.PathValue("replyID")

	replyID, err := uuid.Parse(replyIDString)
	if err != nil {
		http.Error(w, "Invalid reply ID", http.StatusBadRequest)
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

	result, err := db.Exec(
		r.Context(),
		`
		DELETE FROM public.replies
		WHERE id = $1
		`,
		replyID,
	)

	if err != nil {
		logger.Error(
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

func createForum(w http.ResponseWriter, r *http.Request) {
	user, err := getUserID(r)
	if err != nil {
		if errors.Is(err, ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		logger.Error(
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

	var input CreateForumRequest

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

	var forum Forum

	err = db.QueryRow(
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
		logger.Error(
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
		logger.Error(
			"failed to encode forum",
			"error", err,
			"status", http.StatusCreated,
		)
	}
}

func updateForum(w http.ResponseWriter, r *http.Request) {
	user, err := getUserID(r)
	if err != nil {
		if errors.Is(err, ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		logger.Error(
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

	var input CreateForumRequest

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

	var forum Forum

	err = db.QueryRow(
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

		logger.Error(
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
		logger.Error(
			"failed to encode forum",
			"error", err,
			"status", http.StatusOK,
		)
	}
}
