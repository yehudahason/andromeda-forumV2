import type { ThreadType } from "../types";
import getToken from "../lib/getToken";
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
  let token;
  const url = "https://api.pitron-halomot.org";
  try {
    token = await getToken();
  } catch (e) {
    console.log(e);
  }
  const response = await fetch(
    `${url}/api/forums/${forumID}/threads?page=${page}`,
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
      },
    },
  );

  if (!response.ok) {
    const error = await response.text();
    throw new Error(error || "Failed to get threads");
  }

  return response.json();
}
