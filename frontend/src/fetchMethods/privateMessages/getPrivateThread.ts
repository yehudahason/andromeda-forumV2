import { privateRequest } from "./privateRequest";
import type { PrivateThreadDetailsResponse } from "./privateTypes";

// GET /api/private/threads/{id}
export function getPrivateThread(
  threadID: number,
  signal?: AbortSignal,
): Promise<PrivateThreadDetailsResponse> {
  return privateRequest(`/api/private/threads/${threadID}`, { signal });
}
