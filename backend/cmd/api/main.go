package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"

	"github.com/MicahParks/keyfunc"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"

	"github.com/yehudahason/andromeda-forumV2/internal/auth"
	"github.com/yehudahason/andromeda-forumV2/internal/handlers"
	"github.com/yehudahason/andromeda-forumV2/internal/server"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := godotenv.Load(); err != nil {
		logger.Error("failed to load .env", "error", err)
		os.Exit(1)
	}
	jwks, err := keyfunc.Get(os.Getenv("JWKS_URL"), keyfunc.Options{})
	if err != nil {
		logger.Error("failed to initialize JWKS", "error", fmt.Errorf("failed to load JWKS: %w", err))
		os.Exit(1)
	}
	ctx := context.Background()
	db, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		logger.Error("failed to connect to database", "error", err)
	}
	defer db.Close()
	if err := db.Ping(ctx); err != nil {
		logger.Error("failed to ping database:", "error", err)
	}
	logger.Info("Connected to PostgreSQL")
	authentication := &auth.Service{DB: db, JWKS: jwks, Logger: logger}
	h := handlers.New(db, logger, authentication)
	mux := server.NewMux(h)
	handler := server.RecoverMiddleware(
		server.LoggerMiddleware(
			server.CORSMiddleware(mux), logger,
		), logger,
	)
	httpServer := &http.Server{Addr: ":4000", Handler: handler}
	logger.Info("server starting", "addr", httpServer.Addr)
	err = httpServer.ListenAndServe()
	if err != nil && err != http.ErrServerClosed {
		logger.Error("server failed", "error", err)
	}
}
