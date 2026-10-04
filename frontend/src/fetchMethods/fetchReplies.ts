import type { ReplyListResponse } from "../types";

export async function getReplies(
  threadID: number | string,
  page = 1,
): Promise<ReplyListResponse> {
  const url = "https://api.pitron-halomot.org";
  const response = await fetch(
    `${url}/api/threads/${threadID}/replies?page=${page}`,
  );

  if (!response.ok) {
    const error = await response.text();
    console.log(error);
    throw new Error(error || "Failed to get replies");
  }

  const log = await response.json();
  console.log(log);
  return log;
}
