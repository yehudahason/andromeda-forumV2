import type { Post } from "../components/PostComposer";
import { getAuthToken } from "../lib/getAuthToken";
import { getReplyPosition } from "./getReplyPosition";

export async function createReply(
  item: Post,
  forum_id: number,
  thread_id: number,
) {
  const token = await getAuthToken();
  const url = "https://api.pitron-halomot.org";
  const res = await fetch(
    `${url}/api/forums/${forum_id}/threads/${thread_id}/replies`,
    {
      method: "POST",

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
    throw new Error(message || "Failed to create reply");
  }
  const data = await res.json();
  let position = await getReplyPosition(thread_id, data.id);
  position = Math.ceil(position / 14);
  const postLink = `/forum/${forum_id}/${thread_id}?tpage=${position}#${data.id}`;
  return postLink;
}
