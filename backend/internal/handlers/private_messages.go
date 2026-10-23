package handlers

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/yehudahason/andromeda-forumV2/internal/auth"
)

const privatePageSize = 14

type privateThread struct {
	ID            int64      `json:"id"`
	Title         *string    `json:"title"`
	CreatedBy     *string    `json:"created_by"`
	LastMessageAt *time.Time `json:"last_message_at"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type privateThreadSummary struct {
	privateThread
	ParticipantsCount int64 `json:"participants_count"`
	UnreadCount       int64 `json:"unread_count"`
}

type privateParticipant struct {
	UserID     string     `json:"user_id"`
	JoinedAt   time.Time  `json:"joined_at"`
	LastReadAt *time.Time `json:"last_read_at"`
}

type privateMessage struct {
	ID        int64     `json:"id"`
	ThreadID  int64     `json:"thread_id"`
	SenderID  *string   `json:"sender_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (h *Handler) RegisterPrivateRoutes(mux *http.ServeMux) {
	mux.HandleFunc("POST /api/private/threads", h.CreatePrivateThread)
	mux.HandleFunc("GET /api/private/threads", h.ListPrivateThreads)
	mux.HandleFunc("GET /api/private/threads/{id}", h.GetPrivateThread)
	mux.HandleFunc("GET /api/private/threads/{id}/messages", h.ListPrivateMessages)
	mux.HandleFunc("POST /api/private/threads/{id}/messages", h.SendPrivateMessage)
	mux.HandleFunc("PUT /api/private/messages/{id}", h.EditPrivateMessage)
	mux.HandleFunc("DELETE /api/private/messages/{id}", h.DeletePrivateMessage)
	mux.HandleFunc("PUT /api/private/threads/{id}/read", h.MarkPrivateThreadRead)
}

func (h *Handler) privateAuth(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	user, err := h.Auth.GetUser(r)
	if err == nil {
		return user.ID, true
	}
	if errors.Is(err, auth.ErrUnauthorized) {
		w.Header().Set("WWW-Authenticate", "Bearer")
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
	} else {
		h.privateInternalError(w, "private message authentication", err)
	}
	return uuid.Nil, false
}

func (h *Handler) privateInternalError(w http.ResponseWriter, operation string, err error) {
	h.Logger.Error(operation, "error", err, "status", http.StatusInternalServerError)
	http.Error(w, "Internal server error", http.StatusInternalServerError)
}

func (h *Handler) privateWriteJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		h.Logger.Error("private message JSON response", "error", err)
	}
}

func (h *Handler) privateDecodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	// Large enough for a 100,000-character UTF-8 message, but bounded.
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(dst); err != nil {
		var sizeErr *http.MaxBytesError
		if errors.As(err, &sizeErr) {
			http.Error(w, "Request body too large", http.StatusRequestEntityTooLarge)
		} else {
			http.Error(w, "Invalid JSON body", http.StatusBadRequest)
		}
		return false
	}
	var trailing any
	if err := decoder.Decode(&trailing); !errors.Is(err, io.EOF) {
		http.Error(w, "Request must contain one JSON object", http.StatusBadRequest)
		return false
	}
	return true
}

func (h *Handler) privatePathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		http.Error(w, "Invalid ID", http.StatusBadRequest)
		return 0, false
	}
	return id, true
}

func (h *Handler) privatePage(w http.ResponseWriter, r *http.Request) (int, bool) {
	page := 1
	if raw := r.URL.Query().Get("page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > 1_000_000 {
			http.Error(w, "Invalid page", http.StatusBadRequest)
			return 0, false
		}
		page = n
	}
	return page, true
}

// Return 404 both for nonexistent conversations and conversations the user
// does not belong to; this avoids disclosing private conversation IDs.

func (h *Handler) privateRequireParticipant(w http.ResponseWriter, r *http.Request, threadID int64, userID uuid.UUID) bool {
	var allowed bool
	err := h.DB.QueryRow(r.Context(), `
		SELECT EXISTS (
			SELECT 1 FROM public.private_thread_participants
			WHERE thread_id = $1 AND user_id = $2
		)
	`, threadID, userID).Scan(&allowed)
	if err != nil {
		h.privateInternalError(w, "check private conversation participant", err)
		return false
	}
	if !allowed {
		http.Error(w, "Conversation not found", http.StatusNotFound)
		return false
	}
	return true
}

// POST /api/private/threads
// Body: {"title":"Optional title", "participant_ids":["recipient-uuid", ...] ,"content":"message"}
// The authenticated user is always added as a participant.

func (h *Handler) CreatePrivateThread(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	// 1. Authenticate user
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}

	// 2. Decode request
	var input struct {
		Title          *string     `json:"title"`
		ParticipantIDs []uuid.UUID `json:"participant_ids"`
		Content        string      `json:"content"`
	}

	if !h.privateDecodeJSON(w, r, &input) {
		return
	}

	// 3. Validate first message
	if !h.privateValidateContent(w, input.Content) {
		return
	}

	// 4. Validate optional title
	if input.Title != nil {
		title := strings.TrimSpace(*input.Title)

		if utf8.RuneCountInString(title) > 255 {
			http.Error(
				w,
				"Title must be 255 characters or fewer",
				http.StatusBadRequest,
			)
			return
		}

		if title == "" {
			input.Title = nil
		} else {
			input.Title = &title
		}
	}

	// 5. Build unique participant list
	// Always include authenticated sender
	members := []uuid.UUID{userID}

	seen := map[uuid.UUID]bool{
		userID: true,
	}

	for _, id := range input.ParticipantIDs {
		if id == uuid.Nil {
			http.Error(w, "Invalid participant ID", http.StatusBadRequest)
			return
		}

		if !seen[id] {
			members = append(members, id)
			seen[id] = true
		}
	}

	if len(members) < 2 || len(members) > 50 {
		http.Error(
			w,
			"A conversation needs 2 to 50 distinct participants",
			http.StatusBadRequest,
		)
		return
	}

	// 6. Begin transaction
	tx, err := h.DB.Begin(ctx)
	if err != nil {
		h.privateInternalError(w, "begin private thread transaction", err)
		return
	}
	defer tx.Rollback(ctx)

	// 7. Create private thread
	var threadID int64

	err = tx.QueryRow(ctx, `
		INSERT INTO public.private_threads (
			title,
			created_by
		)
		VALUES ($1, $2)
		RETURNING id
	`,
		input.Title,
		userID,
	).Scan(&threadID)

	if err != nil {
		h.privateInternalError(w, "create private thread", err)
		return
	}

	// 8. Insert participants
	for _, memberID := range members {
		_, err = tx.Exec(ctx, `
			INSERT INTO public.private_thread_participants (
				thread_id,
				user_id
			)
			VALUES ($1, $2)
		`,
			threadID,
			memberID,
		)

		if err != nil {
			var pgErr *pgconn.PgError

			if errors.As(err, &pgErr) && pgErr.Code == "23503" {
				http.Error(
					w,
					"One or more participants do not exist",
					http.StatusBadRequest,
				)
			} else {
				h.privateInternalError(w, "insert private participant", err)
			}
			return
		}
	}

	// 9. Insert first message
	var message privateMessage

	err = tx.QueryRow(ctx, `
		INSERT INTO public.private_messages (
			thread_id,
			sender_id,
			content
		)
		VALUES ($1, $2, $3)
		RETURNING
			id,
			thread_id,
			sender_id::text,
			content,
			created_at,
			updated_at
	`,
		threadID,
		userID,
		input.Content,
	).Scan(
		&message.ID,
		&message.ThreadID,
		&message.SenderID,
		&message.Content,
		&message.CreatedAt,
		&message.UpdatedAt,
	)

	if err != nil {
		h.privateInternalError(w, "insert first private message", err)
		return
	}

	// 10. Mark sender's conversation as read
	_, err = tx.Exec(ctx, `
		UPDATE public.private_thread_participants
		SET last_read_at = $3
		WHERE thread_id = $1
		  AND user_id = $2
	`,
		threadID,
		userID,
		message.CreatedAt,
	)

	if err != nil {
		h.privateInternalError(w, "mark private thread read", err)
		return
	}

	// 11. Fetch thread after message insertion.
	// The database trigger maintains last_message_at.
	var thread privateThread

	err = tx.QueryRow(ctx, `
		SELECT
			id,
			title,
			created_by::text,
			last_message_at,
			created_at,
			updated_at
		FROM public.private_threads
		WHERE id = $1
	`, threadID).Scan(
		&thread.ID,
		&thread.Title,
		&thread.CreatedBy,
		&thread.LastMessageAt,
		&thread.CreatedAt,
		&thread.UpdatedAt,
	)

	if err != nil {
		h.privateInternalError(w, "fetch created private thread", err)
		return
	}

	// 12. Commit all operations
	if err := tx.Commit(ctx); err != nil {
		h.privateInternalError(w, "commit private thread transaction", err)
		return
	}

	// 13. Return created thread and first message
	h.privateWriteJSON(w, http.StatusCreated, struct {
		Thread         privateThread  `json:"thread"`
		Message        privateMessage `json:"message"`
		ParticipantIDs []uuid.UUID    `json:"participant_ids"`
	}{
		Thread:         thread,
		Message:        message,
		ParticipantIDs: members,
	})
}

// GET /api/private/threads?page=1

func (h *Handler) ListPrivateThreads(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}
	page, ok := h.privatePage(w, r)
	if !ok {
		return
	}

	var total int64
	err := h.DB.QueryRow(r.Context(), `
		SELECT COUNT(*) FROM public.private_thread_participants WHERE user_id = $1
	`, userID).Scan(&total)
	if err != nil {
		h.privateInternalError(w, "count private threads", err)
		return
	}

	rows, err := h.DB.Query(r.Context(), `
		SELECT
			t.id, t.title, t.created_by::text, t.last_message_at,
			t.created_at, t.updated_at,
			(SELECT COUNT(*) FROM public.private_thread_participants AS others
			 WHERE others.thread_id = t.id) AS participants_count,
			(SELECT COUNT(*) FROM public.private_messages AS m
			 WHERE m.thread_id = t.id
			   AND m.sender_id IS DISTINCT FROM $1
			   AND (p.last_read_at IS NULL OR m.created_at > p.last_read_at)
			) AS unread_count
		FROM public.private_thread_participants AS p
		JOIN public.private_threads AS t ON t.id = p.thread_id
		WHERE p.user_id = $1
		ORDER BY t.last_message_at DESC NULLS LAST, t.created_at DESC, t.id DESC
		LIMIT $2 OFFSET $3
	`, userID, privatePageSize, (page-1)*privatePageSize)
	if err != nil {
		h.privateInternalError(w, "query private threads", err)
		return
	}
	defer rows.Close()

	threads := make([]privateThreadSummary, 0)
	for rows.Next() {
		var t privateThreadSummary
		err := rows.Scan(
			&t.ID, &t.Title, &t.CreatedBy, &t.LastMessageAt,
			&t.CreatedAt, &t.UpdatedAt, &t.ParticipantsCount, &t.UnreadCount,
		)
		if err != nil {
			h.privateInternalError(w, "scan private threads", err)
			return
		}
		threads = append(threads, t)
	}
	if err := rows.Err(); err != nil {
		h.privateInternalError(w, "iterate private threads", err)
		return
	}

	h.privateWriteJSON(w, http.StatusOK, struct {
		Threads []privateThreadSummary `json:"threads"`
		Total   int64                  `json:"total"`
		Page    int                    `json:"page"`
		PerPage int                    `json:"per_page"`
	}{Threads: threads, Total: total, Page: page, PerPage: privatePageSize})
}

// GET /api/private/threads/{id}

func (h *Handler) GetPrivateThread(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}
	threadID, ok := h.privatePathID(w, r)
	if !ok {
		return
	}

	var thread privateThread
	err := h.DB.QueryRow(r.Context(), `
		SELECT t.id, t.title, t.created_by::text, t.last_message_at,
		       t.created_at, t.updated_at
		FROM public.private_threads AS t
		JOIN public.private_thread_participants AS member
		  ON member.thread_id = t.id AND member.user_id = $2
		WHERE t.id = $1
	`, threadID, userID).Scan(
		&thread.ID, &thread.Title, &thread.CreatedBy,
		&thread.LastMessageAt, &thread.CreatedAt, &thread.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		http.Error(w, "Conversation not found", http.StatusNotFound)
		return
	}
	if err != nil {
		h.privateInternalError(w, "get private thread", err)
		return
	}

	rows, err := h.DB.Query(r.Context(), `
		SELECT user_id::text, joined_at, last_read_at
		FROM public.private_thread_participants
		WHERE thread_id = $1
		  AND EXISTS (
			SELECT 1 FROM public.private_thread_participants
			WHERE thread_id = $1 AND user_id = $2
		  )
		ORDER BY joined_at, user_id
	`, threadID, userID)
	if err != nil {
		h.privateInternalError(w, "list private participants", err)
		return
	}
	defer rows.Close()

	participants := make([]privateParticipant, 0)
	for rows.Next() {
		var p privateParticipant
		if err := rows.Scan(&p.UserID, &p.JoinedAt, &p.LastReadAt); err != nil {
			h.privateInternalError(w, "scan private participants", err)
			return
		}
		participants = append(participants, p)
	}
	if err := rows.Err(); err != nil {
		h.privateInternalError(w, "iterate private participants", err)
		return
	}
	h.privateWriteJSON(w, http.StatusOK, struct {
		Thread       privateThread        `json:"thread"`
		Participants []privateParticipant `json:"participants"`
	}{Thread: thread, Participants: participants})
}

// GET /api/private/threads/{id}/messages?page=1

func (h *Handler) ListPrivateMessages(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}
	threadID, ok := h.privatePathID(w, r)
	if !ok {
		return
	}
	page, ok := h.privatePage(w, r)
	if !ok {
		return
	}
	if !h.privateRequireParticipant(w, r, threadID, userID) {
		return
	}

	var total int64
	err := h.DB.QueryRow(r.Context(), `
		SELECT COUNT(*) FROM public.private_messages AS m
		WHERE m.thread_id = $1
		  AND EXISTS (
		    SELECT 1 FROM public.private_thread_participants
		    WHERE thread_id = $1 AND user_id = $2
		  )
	`, threadID, userID).Scan(&total)
	if err != nil {
		h.privateInternalError(w, "count private messages", err)
		return
	}

	rows, err := h.DB.Query(r.Context(), `
		SELECT m.id, m.thread_id, m.sender_id::text, m.content,
		       m.created_at, m.updated_at
		FROM public.private_messages AS m
		WHERE m.thread_id = $1
		  AND EXISTS (
		    SELECT 1 FROM public.private_thread_participants
		    WHERE thread_id = $1 AND user_id = $2
		  )
		ORDER BY m.created_at ASC, m.id ASC
		LIMIT $3 OFFSET $4
	`, threadID, userID, privatePageSize, (page-1)*privatePageSize)
	if err != nil {
		h.privateInternalError(w, "query private messages", err)
		return
	}
	defer rows.Close()

	messages := make([]privateMessage, 0)
	for rows.Next() {
		var m privateMessage
		if err := rows.Scan(
			&m.ID, &m.ThreadID, &m.SenderID,
			&m.Content, &m.CreatedAt, &m.UpdatedAt,
		); err != nil {
			h.privateInternalError(w, "scan private messages", err)
			return
		}
		messages = append(messages, m)
	}
	if err := rows.Err(); err != nil {
		h.privateInternalError(w, "iterate private messages", err)
		return
	}

	h.privateWriteJSON(w, http.StatusOK, struct {
		Messages []privateMessage `json:"messages"`
		Total    int64            `json:"total"`
		Page     int              `json:"page"`
		PerPage  int              `json:"per_page"`
	}{Messages: messages, Total: total, Page: page, PerPage: privatePageSize})
}

func (h *Handler) privateValidateContent(w http.ResponseWriter, content string) bool {
	trimmed := strings.TrimSpace(content)
	if trimmed == "" || utf8.RuneCountInString(strings.Trim(content, " ")) > 100_000 {
		http.Error(w, "Content must contain 1 to 100000 characters", http.StatusBadRequest)
		return false
	}
	return true
}

// POST /api/private/threads/{id}/messages
// Body: {"content":"Hello"}

func (h *Handler) SendPrivateMessage(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}
	threadID, ok := h.privatePathID(w, r)
	if !ok {
		return
	}
	var input struct {
		Content string `json:"content"`
	}
	if !h.privateDecodeJSON(w, r, &input) {
		return
	}
	if !h.privateValidateContent(w, input.Content) {
		return
	}

	var message privateMessage
	err := h.DB.QueryRow(r.Context(), `
		INSERT INTO public.private_messages (thread_id, sender_id, content)
		SELECT $1, $2, $3
		WHERE EXISTS (
		    SELECT 1 FROM public.private_thread_participants
		    WHERE thread_id = $1 AND user_id = $2
		)
		RETURNING id, thread_id, sender_id::text, content, created_at, updated_at
	`, threadID, userID, input.Content).Scan(
		&message.ID, &message.ThreadID, &message.SenderID,
		&message.Content, &message.CreatedAt, &message.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		http.Error(w, "Conversation not found", http.StatusNotFound)
		return
	}
	if err != nil {
		h.privateInternalError(w, "send private message", err)
		return
	}
	h.privateWriteJSON(w, http.StatusCreated, message)
}

// PUT /api/private/messages/{id}
// Body: {"content":"Edited text"}

func (h *Handler) EditPrivateMessage(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}
	messageID, ok := h.privatePathID(w, r)
	if !ok {
		return
	}
	var input struct {
		Content string `json:"content"`
	}
	if !h.privateDecodeJSON(w, r, &input) {
		return
	}
	if !h.privateValidateContent(w, input.Content) {
		return
	}

	var message privateMessage
	err := h.DB.QueryRow(r.Context(), `
		UPDATE public.private_messages AS m
		SET content = $1
		WHERE m.id = $2
		  AND m.sender_id = $3
		  AND EXISTS (
		    SELECT 1 FROM public.private_thread_participants AS p
		    WHERE p.thread_id = m.thread_id AND p.user_id = $3
		  )
		RETURNING m.id, m.thread_id, m.sender_id::text, m.content, m.created_at, m.updated_at
	`, input.Content, messageID, userID).Scan(
		&message.ID, &message.ThreadID, &message.SenderID,
		&message.Content, &message.CreatedAt, &message.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		http.Error(w, "Message not found", http.StatusNotFound)
		return
	}
	if err != nil {
		h.privateInternalError(w, "edit private message", err)
		return
	}
	h.privateWriteJSON(w, http.StatusOK, message)
}

// DELETE /api/private/messages/{id}

func (h *Handler) DeletePrivateMessage(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}
	messageID, ok := h.privatePathID(w, r)
	if !ok {
		return
	}

	var deletedID int64
	err := h.DB.QueryRow(r.Context(), `
		DELETE FROM public.private_messages AS m
		WHERE m.id = $1 AND m.sender_id = $2
		  AND EXISTS (
		    SELECT 1 FROM public.private_thread_participants AS p
		    WHERE p.thread_id = m.thread_id AND p.user_id = $2
		  )
		RETURNING m.id
	`, messageID, userID).Scan(&deletedID)
	if errors.Is(err, pgx.ErrNoRows) {
		http.Error(w, "Message not found", http.StatusNotFound)
		return
	}
	if err != nil {
		h.privateInternalError(w, "delete private message", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// PUT /api/private/threads/{id}/read
// Marks messages currently in the conversation as read, never moving
// last_read_at backwards.

func (h *Handler) MarkPrivateThreadRead(w http.ResponseWriter, r *http.Request) {
	userID, ok := h.privateAuth(w, r)
	if !ok {
		return
	}
	threadID, ok := h.privatePathID(w, r)
	if !ok {
		return
	}

	var readAt time.Time
	err := h.DB.QueryRow(r.Context(), `
		UPDATE public.private_thread_participants AS p
		SET last_read_at = GREATEST(
		    p.last_read_at,
		    COALESCE(
		      (SELECT MAX(m.created_at)
		       FROM public.private_messages AS m
		       WHERE m.thread_id = $1),
		      clock_timestamp()
		    )
		)
		WHERE p.thread_id = $1 AND p.user_id = $2
		RETURNING p.last_read_at
	`, threadID, userID).Scan(&readAt)
	if errors.Is(err, pgx.ErrNoRows) {
		http.Error(w, "Conversation not found", http.StatusNotFound)
		return
	}
	if err != nil {
		h.privateInternalError(w, "mark private conversation read", err)
		return
	}
	h.privateWriteJSON(w, http.StatusOK, struct {
		ThreadID   int64     `json:"thread_id"`
		LastReadAt time.Time `json:"last_read_at"`
	}{ThreadID: threadID, LastReadAt: readAt})
}
