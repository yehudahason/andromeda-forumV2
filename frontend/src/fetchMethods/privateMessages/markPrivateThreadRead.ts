import { privateRequest } from "./privateRequest";
import type { PrivateThreadReadResponse } from "./privateTypes";

// PUT /api/private/threads/{id}/read
export function markPrivateThreadRead(
  threadID: number,
  signal?: AbortSignal,
): Promise<PrivateThreadReadResponse> {
  return privateRequest(`/api/private/threads/${threadID}/read`, {
    method: "PUT",
    signal,
  });
}
