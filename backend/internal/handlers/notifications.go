package handlers

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/yehudahason/andromeda-forumV2/backend/internal/models"
)

const (
	ThreadReply    models.NotificationType = "thread_reply"
	PrivateMessage models.NotificationType = "private_message"
)

type Notification struct {
	ID         int64     `json:"id"`
	UserID     string    `json:"user_id"`
	Type       string    `json:"type"`
	ThreadID   *int64    `json:"thread_id"`
	ThreadPage *int64    `json:"thread_page"`
	ReplyID    *string   `json:"reply_id"`
	MessageID  *int64    `json:"message_id"`
	ActorID    *string   `json:"actor_id"`
	IsRead     bool      `json:"is_read"`
	CreatedAt  time.Time `json:"created_at"`
}

func (h *Handler) GetNotifications(w http.ResponseWriter, r *http.Request) {
	user, err := h.Auth.GetUser(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	rows, err := h.DB.Query(r.Context(), `
		SELECT
			id,
			user_id::text,
			type,
			thread_id,
			thread_page,
			reply_id::text,
			message_id,
			actor_id::text,
			is_read,
			created_at
		FROM public.notifications
		WHERE user_id = $1
		ORDER BY created_at DESC, id DESC
	`, user.ID)

	if err != nil {
		http.Error(w, "Failed to fetch notifications", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	notifications := make([]Notification, 0)

	for rows.Next() {
		var n Notification

		err := rows.Scan(
			&n.ID,
			&n.UserID,
			&n.Type,
			&n.ThreadID,
			&n.ThreadPage,
			&n.ReplyID,
			&n.MessageID,
			&n.ActorID,
			&n.IsRead,
			&n.CreatedAt,
		)

		if err != nil {
			http.Error(w, "Failed to scan notification", http.StatusInternalServerError)
			return
		}

		notifications = append(notifications, n)
	}

	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to read notifications", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(notifications)
}

func (h *Handler) MarkNotificationRead(w http.ResponseWriter, r *http.Request) {
	user, err := h.Auth.GetUser(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	notificationID, err := strconv.ParseInt(
		r.PathValue("id"), 10, 64,
	)

	if err != nil || notificationID <= 0 {
		http.Error(w, "Invalid notification ID", http.StatusBadRequest)
		return
	}

	result, err := h.DB.Exec(r.Context(), `
		UPDATE public.notifications
		SET is_read = TRUE
		WHERE id = $1
		  AND user_id = $2
	`, notificationID, user.ID)

	if err != nil {
		http.Error(w, "Failed to update notification", http.StatusInternalServerError)
		return
	}

	if result.RowsAffected() == 0 {
		http.Error(w, "Notification not found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) MarkAllNotificationsRead(w http.ResponseWriter, r *http.Request) {
	user, err := h.Auth.GetUser(r)
	if err != nil {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	_, err = h.DB.Exec(r.Context(), `
		UPDATE public.notifications
		SET is_read = TRUE
		WHERE user_id = $1
		  AND is_read = FALSE
	`, user.ID)

	if err != nil {
		http.Error(w, "Failed to update notifications", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
func (h *Handler) InsertNotification(
	ctx context.Context,
	db *sql.DB,
	userID string,
	actorID string,
	notificationType models.NotificationType,
	threadID *int64,
	replyID *string,
	messageID *int64,
) error {

	switch notificationType {
	case ThreadReply:
		if threadID == nil || replyID == nil || messageID != nil {
			return errors.New("thread reply requires threadID and replyID")
		}

	case PrivateMessage:
		if messageID == nil || threadID != nil || replyID != nil {
			return errors.New("private message requires messageID")
		}

	default:
		return errors.New("invalid notification type")
	}

	const query = `
		INSERT INTO public.notifications (
			user_id,
			actor_id,
			type,
			thread_id,
			reply_id,
			message_id
		)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT DO NOTHING
	`

	_, err := db.ExecContext(
		ctx,
		query,
		userID,
		actorID,
		notificationType,
		threadID,
		replyID,
		messageID,
	)

	return err
}

func (h *Handler) NotifyThreadFollowers(
	ctx context.Context,
	threadID int64,
	replyID uuid.UUID,
	actorID uuid.UUID,
) error {

	const query = `
		INSERT INTO public.notifications (
			user_id,
			actor_id,
			type,
			thread_id,
			reply_id
		)
		SELECT
			tf.user_id,
			$3,
			'thread_reply',
			$1,
			$2::uuid
		FROM public.thread_follows AS tf
		WHERE tf.thread_id = $1
		  AND tf.user_id <> $3::uuid
		ON CONFLICT DO NOTHING
	`

	_, err := h.DB.Exec(
		ctx,
		query,
		threadID,
		replyID,
		actorID,
	)

	return err
}

// Follow thread func
