import { privateRequest } from "./privateRequest";

export interface Notification {
  id: number;
  user_id: string; //Who receive message
  type: "thread_reply" | "private_message";
  thread_id: number | null;
  thread_page: number | null;
  forum_id: number | null;
  thread_title: string | "";
  reply_id: string | null;
  message_id: number | null;
  actor_id: string | null;
  actor_name: string | null; //Who sent message
  is_read: boolean;
  created_at: string;
}

// Get all notifications
export function getNotifications(
  signal?: AbortSignal,
): Promise<Notification[]> {
  return privateRequest("/api/notifications", {
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
