import { privateRequest } from "./privateRequest";

// DELETE /api/private/threads/{id}
export function deletePrivateThread(
  threadID: number,
  signal?: AbortSignal,
): Promise<void> {
  return privateRequest<void>(`/api/private/threads/${threadID}`, {
    method: "DELETE",
    signal,
  });
}
