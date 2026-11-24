package server

import (
	"net/http"

	"github.com/yehudahason/andromeda-forumV2/backend/internal/handlers"
)

func NewMux(h *handlers.Handler) *http.ServeMux {
	mux := http.NewServeMux()
	//Public Endpoints
	mux.HandleFunc("GET /api/forums", h.GetForums)
	mux.HandleFunc("GET /api/forums/{forumID}/threads", h.GetThreads)
	mux.HandleFunc("GET /api/threads/{threadID}/replies", h.GetReplies)
	mux.HandleFunc("GET /api/threads/{threadID}", h.GetThreadByID)
	mux.HandleFunc("GET /api/replies/{replyID}", h.GetReplyByID)
	mux.HandleFunc("GET /api/posts/latest", h.GetLatestPosts)
	mux.HandleFunc("GET /api/replies/{threadID}/{replyID}/position", h.GetReplyPositionHandler)
	mux.HandleFunc("GET /api/users/{id}", h.GetUserByIDEndpoint)
	mux.HandleFunc("GET /api/users/{id}/threads", h.GetUserThreads)
	mux.HandleFunc("GET /api/users/{id}/replies", h.GetUserReplies)

	//Authorized endpoints
	mux.HandleFunc("DELETE /api/private/threads/{id}", h.DeletePrivateThread)
	mux.HandleFunc(
		"DELETE /api/private/threads",
		h.DeleteAllPrivateThreads,
	)
	mux.HandleFunc("PATCH /api/me/image", h.UpdateProfileImage)
	mux.HandleFunc("PUT /api/notifications/read-all", h.MarkAllNotificationsRead)
	mux.HandleFunc("GET /api/notifications", h.GetNotifications)
	mux.HandleFunc("PUT /api/notifications/{id}/read", h.MarkNotificationRead)
	mux.HandleFunc("POST /api/threads/{threadID}/follow", h.FollowThreadHandler)
	mux.HandleFunc("DELETE /api/threads/{threadID}/follow", h.UnfollowThreadHandler)
	mux.HandleFunc("GET /api/threads/{threadID}/follow", h.GetThreadFollow)
	mux.HandleFunc("DELETE /api/forums/{forumID}", h.DeleteForum)
	mux.HandleFunc("POST /api/forums", h.CreateForum)
	mux.HandleFunc("PUT /api/forums/{forumID}", h.UpdateForum)
	mux.HandleFunc("DELETE /api/threads/{threadID}", h.DeleteThread)
	mux.HandleFunc("DELETE /api/replies/{replyID}", h.DeleteReply)
	mux.HandleFunc("POST /api/forums/{forumID}/threads", h.CreateThread)
	mux.HandleFunc("PUT /api/threads/{threadID}", h.UpdateThread)
	mux.HandleFunc("PUT /api/replies/{replyID}", h.UpdateReply)
	mux.HandleFunc("POST /api/upload", h.UploadImageHandler)
	mux.HandleFunc("GET /api/me", h.MeHandler)
	mux.HandleFunc(
		"POST /api/forums/{forumID}/threads/{threadID}/replies",
		h.CreateReply,
	)
	//Private messages endpionts
	h.RegisterPrivateRoutes(mux)
	return mux
}
