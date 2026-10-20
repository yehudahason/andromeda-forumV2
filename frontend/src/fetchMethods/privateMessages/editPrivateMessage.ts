import { privateRequest } from "./privateRequest";
import type { PrivateMessage } from "./privateTypes";

// PUT /api/private/messages/{id}
export function editPrivateMessage(
  messageID: number,
  content: string,
  signal?: AbortSignal,
): Promise<PrivateMessage> {
  return privateRequest(`/api/private/messages/${messageID}`, {
    method: "PUT",
    body: { content },
    signal,
  });
}
