import { getAuthToken } from "../lib/getAuthToken";
import type { LatestPost } from "../types";
export async function getLatestPosts(page: number = 1): Promise<LatestPost[]> {
  const url = "https://api.pitron-halomot.org";
  let token;
  try {
    token = await getAuthToken();
  } catch (e) {
    console.log(e);
    token = null;
  }
  const res = await fetch(
    `${url}/api/posts/latest?page=${page}`,

    {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
    },
  );

  if (!res.ok) {
    const message = await res.text();
    throw new Error(message || "Failed to fetch latest posts");
  }

  return res.json();
}
