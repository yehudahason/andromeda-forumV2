import { privateRequest } from "./privateRequest";
import type { PrivateMessagesResponse } from "./privateTypes";

// GET /api/private/threads/{id}/messages?page=1
export function getPrivateMessages(
  threadID: number,
  page = 1,
  signal?: AbortSignal,
): Promise<PrivateMessagesResponse> {
  return privateRequest(
    `/api/private/threads/${threadID}/messages?page=${page}`,
    { signal },
  );
}
