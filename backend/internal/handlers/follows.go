package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/google/uuid"
	"github.com/yehudahason/andromeda-forumV2/internal/auth"
)

func (h *Handler) FollowThread(
	ctx context.Context,
	userID uuid.UUID,
	threadID int64,
) error {
	const query = `
        INSERT INTO public.thread_follows (
            user_id,
            thread_id
        )
        VALUES ($1, $2)
        ON CONFLICT DO NOTHING
    `

	_, err := h.DB.Exec(
		ctx,
		query,
		userID,
		threadID,
	)

	return err
}

//UnFollow thread func

func (h *Handler) UnfollowThread(
	ctx context.Context,
	userID uuid.UUID,
	threadID int64,
) error {
	const query = `
        DELETE FROM public.thread_follows
        WHERE user_id = $1
          AND thread_id = $2
    `

	_, err := h.DB.Exec(ctx, query, userID, threadID)
	return err
}

//Follow thread endpoint

func (h *Handler) FollowThreadHandler(w http.ResponseWriter, r *http.Request) {
	threadID, err := strconv.ParseInt(r.PathValue("threadID"), 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	userID, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error("followThread authentication failed", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	err = h.FollowThread(r.Context(), userID.ID, threadID)
	if err != nil {
		h.Logger.Error("followThread database error", "error", err)
		http.Error(w, "Failed to follow thread", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// UnFollow thread endpoint

func (h *Handler) UnfollowThreadHandler(w http.ResponseWriter, r *http.Request) {
	threadID, err := strconv.ParseInt(r.PathValue("threadID"), 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	userID, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error("unfollowThread authentication failed", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	err = h.UnfollowThread(r.Context(), userID.ID, threadID)
	if err != nil {
		h.Logger.Error("unfollowThread database error", "error", err)
		http.Error(w, "Failed to unfollow thread", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// isFollow Thread endpoint

func (h *Handler) GetThreadFollow(w http.ResponseWriter, r *http.Request) {
	threadID, err := strconv.ParseInt(r.PathValue("threadID"), 10, 64)
	if err != nil || threadID <= 0 {
		http.Error(w, "Invalid thread ID", http.StatusBadRequest)
		return
	}

	// Authenticate user
	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error("getThreadFollow authentication failed", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Check if user follows thread
	following, err := h.IsThreadFollowed(r.Context(), user.ID, threadID)
	if err != nil {
		h.Logger.Error("getThreadFollow database error", "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	// Return JSON response
	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(struct {
		Following bool `json:"following"`
	}{
		Following: following,
	}); err != nil {
		h.Logger.Error("getThreadFollow JSON encoding error", "error", err)
	}
}

// IsThread Followed func

func (h *Handler) IsThreadFollowed(
	ctx context.Context,
	userID uuid.UUID,
	threadID int64,
) (bool, error) {
	const query = `
        SELECT EXISTS (
            SELECT 1
            FROM public.thread_follows
            WHERE user_id = $1
              AND thread_id = $2
        )
    `

	var following bool

	err := h.DB.QueryRow(
		ctx,
		query,
		userID,
		threadID,
	).Scan(&following)

	return following, err
}
