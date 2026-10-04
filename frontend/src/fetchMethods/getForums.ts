import type { ForumType } from "../types";

export async function getForums(): Promise<ForumType[]> {
  const url = "https://api.pitron-halomot.org";
  const response = await fetch(`${url}/api/forums`);

  if (!response.ok) {
    const error = await response.text();
    throw new Error(error || "Failed to get forums");
  }

  return response.json();
}
