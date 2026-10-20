import { privateRequest } from "./privateRequest";
import type { PrivateThreadListResponse } from "./privateTypes";

// GET /api/private/threads?page=1
export function getPrivateThreads(
  page = 1,
  signal?: AbortSignal,
): Promise<PrivateThreadListResponse> {
  return privateRequest(`/api/private/threads?page=${page}`, { signal });
}
