package handlers

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/yehudahason/andromeda-forumV2/internal/auth"
)

func (h *Handler) DeleteThread(w http.ResponseWriter, r *http.Request) {
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

	result, err := h.DB.Exec(
		r.Context(),
		`
		DELETE FROM public.threads
		WHERE id = $1
		`,
		threadID,
	)

	if err != nil {
		h.Logger.Error(
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
