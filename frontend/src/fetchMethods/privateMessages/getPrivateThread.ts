import { privateRequest } from "./privateRequest";
import type { PrivateThreadResponse } from "./privateTypes";

// GET /api/private/threads/{id}/messages?page=1
export function getPrivateThread(
  threadID: number,
  page = 1,
  signal?: AbortSignal,
): Promise<PrivateThreadResponse> {
  return privateRequest(
    `/api/private/threads/${threadID}/messages?page=${page}`,
    { signal },
  );
}
