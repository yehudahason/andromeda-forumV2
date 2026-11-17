import { privateRequest } from "./privateRequest";

export interface Notification {
  id: number;
  user_id: string; //Who receive notification
  type: "thread_reply" | "private_message";
  thread_id: number | null; //thread id
  thread_page: number | null;
  forum_id: number | null;
  thread_title: string | "";
  reply_id: string | null;
  message_id: number | null;
  private_thread_id: number | null; //private-message thread id
  actor_id: string | null;
  actor_name: string | null; // Who trigger notification
  is_read: boolean;
  created_at: string;
}

export interface NotificationResponse {
  notifications: Notification[];
  total: number;
  page: number;
  total_pages: number;
}
// Get all notifications
export function getNotifications(
  page: number,
  signal?: AbortSignal,
): Promise<NotificationResponse> {
  return privateRequest(`/api/notifications?page=${page}`, {
    method: "GET",
    signal,
  });
}

// Mark one notification as read
export function markNotificationRead(
  notificationID: number,
  signal?: AbortSignal,
): Promise<void> {
  return privateRequest(`/api/notifications/${notificationID}/read`, {
    method: "PUT",
    signal,
  });
}

// Mark all notifications as read
export function markAllNotificationsRead(signal?: AbortSignal): Promise<void> {
  return privateRequest("/api/notifications/read-all", {
    method: "PUT",
    signal,
  });
}
