import { privateRequest } from "./privateRequest";

// DELETE /api/private/messages/{id}
export function deletePrivateMessage(
  messageID: number,
  signal?: AbortSignal,
): Promise<{
  thread_deleted: boolean;
}> {
  return privateRequest<{
    thread_deleted: boolean;
  }>(`/api/private/messages/${messageID}`, {
    method: "DELETE",
    signal,
  });
}
