import getToken from "../lib/getToken";
import type { Post } from "../components/PostComposer";
import type { CreateThreadResponse } from "../types";

export async function createThread(
  item: Post,
  forum_id: number,
): Promise<CreateThreadResponse> {
  const token = await getToken();
  const url = "https://api.pitron-halomot.org";

  const res = await fetch(`${url}/api/forums/${forum_id}/threads`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      title: item.title,
      content: item.content,
      notify: item.notify,
    }),
  });

  if (!res.ok) {
    const message = await res.text();
    throw new Error(message || "Failed to create thread");
  }

  const data: CreateThreadResponse = await res.json();

  return data;
}
