package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"

	"github.com/MicahParks/keyfunc"
)

var jwks *keyfunc.JWKS

// PostgreSQL connection pool.
var db *pgxpool.Pool

func initJWKS() error {
	var err error

	jwks, err = keyfunc.Get(os.Getenv("JWKS_URL"), keyfunc.Options{})
	if err != nil {
		return fmt.Errorf("failed to load JWKS: %w", err)
	}

	return nil
}

var logger = slog.New(
	slog.NewJSONHandler(os.Stdout, nil),
)

type responseWriter struct {
	http.ResponseWriter
	status int
	size   int
}

func (rw *responseWriter) WriteHeader(status int) {
	rw.status = status
	rw.ResponseWriter.WriteHeader(status)
}

func (rw *responseWriter) Write(data []byte) (int, error) {
	if rw.status == 0 {
		rw.status = http.StatusOK
	}

	n, err := rw.ResponseWriter.Write(data)
	rw.size += n

	return n, err
}

func loggerMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()

		rw := &responseWriter{
			ResponseWriter: w,
			status:         http.StatusOK,
		}

		next.ServeHTTP(rw, r)

		logger.Info(
			"http request",
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", rw.status),
			slog.Int("bytes", rw.size),
			slog.Duration("duration", time.Since(start)),
			slog.String("remote_addr", r.RemoteAddr),
		)
	})
}
func main() {

	if err := godotenv.Load(); err != nil {
		logger.Error("failed to load .env", "error", err)
		os.Exit(1)
	}

	if err := initJWKS(); err != nil {
		logger.Error("failed to initialize JWKS", "error", err)
		os.Exit(1)
	}
	ctx := context.Background()

	// Initialize PostgreSQL connection pool
	var err error
	db, err = pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		logger.Error("failed to connect to database", "error", err)
	}
	defer db.Close()

	// Verify the connection
	if err := db.Ping(ctx); err != nil {
		logger.Error("failed to ping database:", "error", err)
	}
	logger.Info("Connected to PostgreSQL")

	mux := http.NewServeMux()
	//Public Endpoints
	mux.HandleFunc("GET /api/forums", getForums)
	mux.HandleFunc("GET /api/forums/{forumID}/threads", getThreads)
	mux.HandleFunc("GET /api/threads/{threadID}/replies", getReplies)
	mux.HandleFunc("GET /api/threads/{threadID}", getThreadByID)
	mux.HandleFunc("GET /api/replies/{replyID}", getReplyByID)
	mux.HandleFunc("GET /api/posts/latest", getLatestPosts)
	mux.HandleFunc("GET /api/replies/{threadID}/{replyID}/position", getReplyPositionHandler)
	mux.HandleFunc("GET /api/users/{id}", getUserByIDEndpoint)

	//Authorized endpoints by Neon better-auth token
	mux.HandleFunc("DELETE /api/forums/{forumID}", deleteForum)
	mux.HandleFunc("POST /api/forums", createForum)
	mux.HandleFunc("PUT /api/forums/{forumID}", updateForum)
	mux.HandleFunc("DELETE /api/threads/{threadID}", deleteThread)
	mux.HandleFunc("DELETE /api/replies/{replyID}", deleteReply)
	mux.HandleFunc("POST /api/forums/{forumID}/threads", createThread)
	mux.HandleFunc("PUT /api/threads/{threadID}", updateThread)
	mux.HandleFunc("PUT /api/replies/{replyID}", updateReply)
	mux.HandleFunc("POST /api/upload", uploadImageHandler)
	mux.HandleFunc("GET /api/me", meHandler)
	mux.HandleFunc(
		"POST /api/forums/{forumID}/threads/{threadID}/replies",
		createReply,
	)

	handler := recoverMiddleware(
		loggerMiddleware(
			corsMiddleware(mux),
		),
	)

	server := &http.Server{
		Addr:    ":4000",
		Handler: handler,
	}

	logger.Info("server starting", "addr", server.Addr)

	err = server.ListenAndServe()
	if err != nil && err != http.ErrServerClosed {
		logger.Error("server failed", "error", err)
	}

}

func recoverMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if err := recover(); err != nil {
				logger.Error(
					"panic recovered",
					"method", r.Method,
					"path", r.URL.Path,
					"error", err,
				)

				http.Error(
					w,
					"Internal Server Error",
					http.StatusInternalServerError,
				)
			}
		}()

		next.ServeHTTP(w, r)
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {

		//Allowed Origins
		allowedOrigins := map[string]bool{
			"http://localhost:5173":          true,
			"https://lab.pitron-halomot.org": true,
		}

		//Headers
		origin := r.Header.Get("Origin")
		if allowedOrigins[origin] {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Add("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			w.Header().Set(
				"Access-Control-Allow-Methods",
				"GET, POST, PUT, DELETE, OPTIONS",
			)
			w.Header().Set(
				"Access-Control-Allow-Headers",
				"Content-Type, Authorization",
			)
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}
