import { getAuthToken } from "../lib/getAuthToken";
import type { ThreadDetails } from "../types";
export async function getThreadByID(
  threadID: number,
  forumId: number,
): Promise<ThreadDetails> {
  const url = "https://api.pitron-halomot.org";
  let token;
  try {
    token = await getAuthToken();
  } catch (e) {
    console.log(e);
    token = null;
  }
  const res = await fetch(`${url}/api/threads/${threadID}?f=${forumId}`, {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
  });

  if (!res.ok) {
    if (res.status === 404) {
      throw new Error("Thread not found");
    }

    throw new Error("Failed to fetch thread");
  }

  return res.json();
}
