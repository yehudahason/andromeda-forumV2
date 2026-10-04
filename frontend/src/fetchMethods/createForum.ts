import { getAuthToken } from "../lib/getAuthToken";

export type CreateForumData = {
  id?: number;
  name: string;
  description: string;
  sort_order: number;
};

export type CreatedForum = {
  id: number;
  name: string;
  description: string;
  sort_order: number;
};

export async function createForum(
  data: CreateForumData,
): Promise<CreatedForum | undefined> {
  const url = "https://api.pitron-halomot.org";

  let token: string;

  try {
    token = await getAuthToken();
  } catch (error) {
    console.error("Failed to get auth token:", error);
    return;
  }

  const response = await fetch(`${url}/api/forums`, {
    method: "POST",
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
