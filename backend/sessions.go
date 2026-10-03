package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

var ErrUnauthorized = errors.New("unauthorized")

func getUserID(r *http.Request) (User, error) {
	authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
	if authHeader == "" {
		return User{}, fmt.Errorf("%w: missing Authorization header", ErrUnauthorized)
	}

	parts := strings.Fields(authHeader)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return User{}, fmt.Errorf("%w: invalid Authorization header", ErrUnauthorized)
	}

	tokenString := strings.TrimSpace(parts[1])
	if tokenString == "" {
		return User{}, fmt.Errorf("%w: missing bearer token", ErrUnauthorized)
	}

	var claims jwt.RegisteredClaims

	token, err := jwt.ParseWithClaims(
		tokenString,
		&claims,
		jwks.Keyfunc,
		jwt.WithValidMethods([]string{
			"RS256",
			"ES256",
			"EdDSA",
		}),
	)
	if err != nil {
		return User{}, fmt.Errorf(
			"%w: invalid token: %v",
			ErrUnauthorized,
			err,
		)
	}

	if !token.Valid {
		return User{}, fmt.Errorf("%w: invalid token", ErrUnauthorized)
	}

	if claims.Subject == "" {
		return User{}, fmt.Errorf("%w: missing user ID", ErrUnauthorized)
	}

	userID, err := uuid.Parse(claims.Subject)
	if err != nil {
		return User{}, fmt.Errorf("%w: invalid user ID", ErrUnauthorized)
	}

	var user User

	err = db.QueryRow(
		r.Context(),
		`
		SELECT
			u.id,
			COALESCE(u.name, ''),
			COALESCE(u.role, 'user'),
			COALESCE(a.email, ''),
			COALESCE(u.image, ''),
			COALESCE(u.replies_count, 0)
		FROM auth.users AS a
		JOIN public.users AS u
			ON u.id = a.id
		WHERE a.id = $1
		`,
		userID,
	).Scan(
		&user.ID,
		&user.Name,
		&user.Role,
		&user.Email,
		&user.Image,
		&user.RepliesCount,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, fmt.Errorf(
				"%w: user not found",
				ErrUnauthorized,
			)
		}

		return User{}, fmt.Errorf(
			"error getting user from db: %w",
			err,
		)
	}

	// Copy external avatar to our own R2 bucket.
	if user.Image != "" {
		r2ImageURL, err := uploadAvatarToR2(
			r.Context(),
			user.ID,
			user.Image,
		)

		if err != nil {
			// Avatar failure must NOT prevent authentication.
			logger.Error(
				"failed to copy avatar to R2",
				"user_id", user.ID,
				"error", err,
				"status", http.StatusInternalServerError,
			)
		} else if r2ImageURL != "" && r2ImageURL != user.Image {

			_, err = db.Exec(
				r.Context(),
				`
				UPDATE public.users
				SET image = $1
				WHERE id = $2
				`,
				r2ImageURL,
				user.ID,
			)

			if err != nil {
				logger.Error(
					"failed to update avatar URL",
					"user_id", user.ID,
					"error", err,
					"status", http.StatusInternalServerError,
				)
			} else {
				user.Image = r2ImageURL
			}
		}
	}

	return user, nil
}
func meHandler(w http.ResponseWriter, r *http.Request) {
	user, err := getUserID(r)
	if err != nil {
		if errors.Is(err, ErrUnauthorized) {
			logger.Warn(
				"authentication failed",
				"error", err,
				"status", http.StatusUnauthorized,
			)

			w.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		logger.Error(
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
		logger.Error(
			"meHandler encode error",
			"error", err,
			"status", http.StatusOK,
		)
	}
}

func getUserByIDEndpoint(w http.ResponseWriter, r *http.Request) {
	userID := r.PathValue("id")

	if userID == "" {
		http.Error(w, "user id is required", http.StatusBadRequest)
		return
	}

	var user User

	err := db.QueryRow(
		r.Context(),
		`
		SELECT
			id,
			name,
			email,
			role,
			image,
			replies_count,
			created_at
		FROM neon_auth."user"
		WHERE id = $1
		`,
		userID,
	).Scan(
		&user.ID,
		&user.Name,
		&user.Email,
		&user.Role,
		&user.Image,
		&user.RepliesCount,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "user not found", http.StatusNotFound)
			return
		}

		logger.Error("failed to get user",
			"error", err,
			"user_id", userID,
			"status", http.StatusInternalServerError,
		)

		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	if err := json.NewEncoder(w).Encode(user); err != nil {
		logger.Error(
			"failed to encode user",
			"error", err,
		)
	}
}
