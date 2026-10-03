package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
)

func deleteForum(w http.ResponseWriter, r *http.Request) {
	forumIDString := r.PathValue("forumID")

	forumID, err := strconv.ParseInt(forumIDString, 10, 64)
	if err != nil || forumID <= 0 {
		http.Error(w, "Invalid forum ID", http.StatusBadRequest)
		return
	}

	userID, err := getUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if userID.Role != "admin" {
		http.Error(w, "Unauthorized non admin", http.StatusUnauthorized)
		return
	}

	result, err := db.Exec(
		r.Context(),
		`
		DELETE FROM forums
		WHERE id = $1
		`,
		forumID,
	)
	if err != nil {
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

	userID, err := getUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if userID.Role != "admin" {
		http.Error(w, "Unauthorized non admin", http.StatusUnauthorized)
		return
	}
	result, err := db.Exec(
		r.Context(),
		`
		DELETE FROM threads
		WHERE id = $1
		`,
		threadID,
	)
	if err != nil {
		http.Error(w, "Failed to delete thread", http.StatusInternalServerError)
		return
	}

	if result.RowsAffected() == 0 {
		http.Error(w, "Thread not found or not owned by user", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func deleteReply(w http.ResponseWriter, r *http.Request) {
	replyID := r.PathValue("replyID")

	if replyID == "" {
		http.Error(w, "Invalid reply ID", http.StatusBadRequest)
		return
	}

	userID, err := getUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if userID.Role != "admin" {
		http.Error(w, "Unauthorized non admin", http.StatusUnauthorized)
		return
	}
	result, err := db.Exec(
		r.Context(),
		`
		DELETE FROM replies
		WHERE id = $1
		`,
		replyID,
	)
	if err != nil {
		http.Error(w, "Failed to delete reply", http.StatusInternalServerError)
		return
	}

	if result.RowsAffected() == 0 {
		http.Error(w, "Reply not found or not owned by user", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func createForum(w http.ResponseWriter, r *http.Request) {

	userID, err := getUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	if userID.Role != "admin" {
		http.Error(w, "Unauthorized non admin", http.StatusUnauthorized)
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

	if input.Name == "" {
		http.Error(w, "Forum name is required", http.StatusBadRequest)
		return
	}

	var forum Forum

	err = db.QueryRow(
		r.Context(),
		`
		INSERT INTO forums (
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
	userID, err := getUserID(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	if userID.Role != "admin" {
		http.Error(w, "Unauthorized non admin", http.StatusUnauthorized)
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

	if input.Name == "" {
		http.Error(w, "Forum name is required", http.StatusBadRequest)
		return
	}

	var forum Forum

	err = db.QueryRow(
		r.Context(),
		`
		UPDATE forums
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
