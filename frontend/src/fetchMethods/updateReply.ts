import type { Post } from "../components/PostComposer";
import { getAuthToken } from "../lib/getAuthToken";

export async function updateReply(item: Post, replyID: string) {
  const token = await getAuthToken();

  const res = await fetch(
    `https://api.pitron-halomot.org/api/replies/${replyID}`,
    {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        post: item.content,
        notify: item.notify,
      }),
    },
  );

  if (!res.ok) {
    const message = await res.text();
    throw new Error(message || "Failed to update reply");
  }

  return res.json();
}
