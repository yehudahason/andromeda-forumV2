package handlers

import (
	"context"
	"database/sql"
	"errors"

	"github.com/google/uuid"
	"github.com/yehudahason/andromeda-forumV2/internal/models"
)

const (
	ThreadReply    models.NotificationType = "thread_reply"
	PrivateMessage models.NotificationType = "private_message"
)

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
