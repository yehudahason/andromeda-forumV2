import type { ThreadType } from "../types";

export type ThreadListResponse = {
  threads: ThreadType[];
  total: number;
  page: number;
  per_page: number;
  forum_name: string;
};

export async function getThreads(
  forumID: string | undefined,
  page = 1,
): Promise<ThreadListResponse> {
  const url = "https://api.pitron-halomot.org";
  const response = await fetch(
    `${url}/api/forums/${forumID}/threads?page=${page}`,
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(error || "Failed to get threads");
  }

  return response.json();
}
