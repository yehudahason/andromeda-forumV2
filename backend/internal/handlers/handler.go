package handlers

import (
	"log/slog"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/yehudahason/andromeda-forumV2/internal/auth"
)

// Handler groups HTTP endpoints and their shared dependencies.
type Handler struct {
	DB     *pgxpool.Pool
	Logger *slog.Logger
	Auth   *auth.Service
}

func New(db *pgxpool.Pool, logger *slog.Logger, authentication *auth.Service) *Handler {
	return &Handler{DB: db, Logger: logger, Auth: authentication}
}
