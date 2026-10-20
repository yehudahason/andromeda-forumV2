import { privateRequest } from "./privateRequest";
import type { CreatePrivateThreadInput, CreatePrivateThreadResponse } from "./privateTypes";

// POST /api/private/threads
export function createPrivateThread(
  input: CreatePrivateThreadInput,
  signal?: AbortSignal,
): Promise<CreatePrivateThreadResponse> {
  return privateRequest("/api/private/threads", {
    method: "POST",
    body: input,
    signal,
  });
}
