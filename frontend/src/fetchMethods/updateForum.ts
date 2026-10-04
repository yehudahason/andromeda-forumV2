import getToken from "../lib/getToken";

import type { CreateForumData, CreatedForum } from "./createForum";

export async function updateForum(
  data: CreateForumData,
): Promise<CreatedForum | undefined> {
  const url = "https://api.pitron-halomot.org";

  let token: string;

  try {
    token = await getToken();
  } catch (error) {
    console.error("Failed to get auth token:", error);
    return;
  }

  const response = await fetch(`${url}/api/forums/${data.id}`, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(data),
  });

  if (!response.ok) {
    const message = await response.text();
    throw new Error(message || "Failed to create forum");
  }

  return response.json();
}
