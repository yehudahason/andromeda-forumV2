import { privateRequest } from "./privateRequest";

// DELETE /api/private/threads
export function deleteAllPrivateThreads(signal?: AbortSignal): Promise<{
  deleted_count: number;
}> {
  return privateRequest<{
    deleted_count: number;
  }>("/api/private/threads", {
    method: "DELETE",
    signal,
  });
}
