import { privateRequest } from "./privateRequest";

// DELETE /api/private/messages/{id}
export function deletePrivateMessage(
  messageID: number,
  signal?: AbortSignal,
): Promise<void> {
  return privateRequest<void>(`/api/private/messages/${messageID}`, {
    method: "DELETE",
    signal,
  });
}
