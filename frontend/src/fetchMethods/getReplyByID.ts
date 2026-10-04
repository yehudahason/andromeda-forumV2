import getToken from "../lib/getToken";
import type { ReplyPost } from "../types";
export async function getReplyByID(replyID: string): Promise<ReplyPost> {
  const url = "https://api.pitron-halomot.org";
  let token;
  try {
    token = await getToken();
  } catch (e) {
    console.log(e);
    token = null;
  }
  const res = await fetch(`${url}/api/replies/${replyID}`, {
    method: "GET",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
  });

  if (!res.ok) {
    if (res.status === 404) {
      throw new Error("Reply not found");
    }

    throw new Error("Failed to fetch reply");
  }

  return res.json();
}
