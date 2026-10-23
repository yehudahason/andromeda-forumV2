package auth

import (
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"github.com/MicahParks/keyfunc"
	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yehudahason/andromeda-forumV2/internal/models"
	"github.com/yehudahason/andromeda-forumV2/internal/storage"
)

// Service owns the dependencies required to authenticate a request.
type Service struct {
	DB     *pgxpool.Pool
	JWKS   *keyfunc.JWKS
	Logger *slog.Logger
}

var ErrUnauthorized = errors.New("unauthorized")

func (a *Service) GetUser(r *http.Request) (models.User, error) {
	authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
	if authHeader == "" {
		return models.User{}, fmt.Errorf("%w: missing Authorization header", ErrUnauthorized)
	}

	parts := strings.Fields(authHeader)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return models.User{}, fmt.Errorf("%w: invalid Authorization header", ErrUnauthorized)
	}

	tokenString := strings.TrimSpace(parts[1])
	if tokenString == "" {
		return models.User{}, fmt.Errorf("%w: missing bearer token", ErrUnauthorized)
	}

	var claims jwt.RegisteredClaims

	token, err := jwt.ParseWithClaims(
		tokenString,
		&claims,
		a.JWKS.Keyfunc,
		jwt.WithValidMethods([]string{
			"RS256",
			"ES256",
			"EdDSA",
		}),
	)
	if err != nil {
		return models.User{}, fmt.Errorf(
			"%w: invalid token: %v",
			ErrUnauthorized,
			err,
		)
	}

	if !token.Valid {
		return models.User{}, fmt.Errorf("%w: invalid token", ErrUnauthorized)
	}

	if claims.Subject == "" {
		return models.User{}, fmt.Errorf("%w: missing user ID", ErrUnauthorized)
	}

	userID, err := uuid.Parse(claims.Subject)
	if err != nil {
		return models.User{}, fmt.Errorf("%w: invalid user ID", ErrUnauthorized)
	}

	var user models.User

	err = a.DB.QueryRow(
		r.Context(),
		`
		SELECT
			p.id,
			p.name,
			p.role,
			COALESCE(a.email, ''),
			COALESCE(p.image_url, ''),
			COALESCE(s.replies_count, 0),
			p.created_at
		FROM auth.users AS a
		JOIN public.profiles AS p
			ON p.auth_user_id = a.id
		LEFT JOIN public.forum_user_stats AS s
			ON s.user_id = a.id
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
		&user.CreatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return models.User{}, fmt.Errorf(
				"%w: user not found",
				ErrUnauthorized,
			)
		}

		return models.User{}, fmt.Errorf(
			"error getting user from db: %w",
			err,
		)
	}

	// Copy external avatar to our own R2 bucket.
	if user.Image != "" {
		r2ImageURL, err := storage.UploadAvatarToR2(
			r.Context(),
			user.ID,
			user.Image,
		)

		if err != nil {
			// Avatar failure must NOT prevent authentication.
			a.Logger.Error(
				"failed to copy avatar to R2",
				"user_id", user.ID,
				"error", err,
				"status", http.StatusInternalServerError,
			)
		} else if r2ImageURL != "" && r2ImageURL != user.Image {

			_, err = a.DB.Exec(
				r.Context(),
				`
				UPDATE public.profiles
				SET
					image_url = $1,
					updated_at = clock_timestamp()
				WHERE id = $2
				`,
				r2ImageURL,
				user.ID,
			)

			if err != nil {
				a.Logger.Error(
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
