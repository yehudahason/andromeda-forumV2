package handlers

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/yehudahason/andromeda-forumV2/internal/auth"
	"github.com/yehudahason/andromeda-forumV2/internal/models"
)

func (h *Handler) MeHandler(w http.ResponseWriter, r *http.Request) {
	user, err := h.Auth.GetUser(r)
	if err != nil {
		if errors.Is(err, auth.ErrUnauthorized) {
			h.Logger.Warn(
				"authentication failed",
				"error", err,
				"status", http.StatusUnauthorized,
			)

			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		h.Logger.Error(
			"meHandler database error",
			"error", err,
			"status", http.StatusInternalServerError,
		)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)

	if err := json.NewEncoder(w).Encode(user); err != nil {
		h.Logger.Error(
			"meHandler encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func (h *Handler) GetUserByIDEndpoint(w http.ResponseWriter, r *http.Request) {
	userIDString := r.PathValue("id")

	userID, err := uuid.Parse(userIDString)
	if err != nil {
		http.Error(w, "Invalid user ID", http.StatusBadRequest)
		return
	}

	var user models.User

	err = h.DB.QueryRow(
		r.Context(),
		`
		SELECT
			p.id,
			p.name,
			COALESCE(a.email, '') AS email,
			p.role,
			COALESCE(p.image_url, '') AS image,
			COALESCE(s.replies_count, 0) AS replies_count,
			p.created_at
		FROM public.profiles AS p

		LEFT JOIN auth.users AS a
			ON a.id = p.auth_user_id

		LEFT JOIN public.forum_user_stats AS s
			ON s.user_id = p.auth_user_id

		WHERE p.id = $1
		`,
		userID,
	).Scan(
		&user.ID,
		&user.Name,
		&user.Email,
		&user.Role,
		&user.Image,
		&user.RepliesCount,
		&user.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "User not found", http.StatusNotFound)
			return
		}

		h.Logger.Error(
			"failed to get user",
			"error", err,
			"user_id", userID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(user); err != nil {
		h.Logger.Error(
			"failed to encode user",
			"error", err,
			"user_id", userID,
			"status", http.StatusOK,
		)
	}
}
