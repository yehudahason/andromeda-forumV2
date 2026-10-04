import type { Post } from "../components/PostComposer";
import { getAuthToken } from "../lib/getAuthToken";

export async function updateThread(item: Post, threadID: number) {
  const token = await getAuthToken();

  const res = await fetch(
    `https://api.pitron-halomot.org/api/threads/${threadID}`,
    {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        title: item.title,
        content: item.content,
        notify: item.notify,
      }),
    },
  );

  if (!res.ok) {
    const message = await res.text();
    throw new Error(message || "Failed to update thread");
  }

  return res.json();
}
