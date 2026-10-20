import { privateRequest } from "./privateRequest";
import type { PrivateMessage } from "./privateTypes";

// POST /api/private/threads/{id}/messages
export function sendPrivateMessage(
  threadID: number,
  content: string,
  signal?: AbortSignal,
): Promise<PrivateMessage> {
  return privateRequest(`/api/private/threads/${threadID}/messages`, {
    method: "POST",
    body: { content },
    signal,
  });
}
