import { type User } from "../types";

export async function getUserByID(
  userID: string,
  signal?: AbortSignal,
): Promise<User> {
  const url = "https://api.pitron-halomot.org";
  const response = await fetch(
    `${url}/api/users/${encodeURIComponent(userID)}`,
    {
      method: "GET",
      signal,
    },
  );

  if (!response.ok) {
    throw new Error(
      response.status === 404
        ? "User not found"
        : `Failed to fetch user: ${response.status}`,
    );
  }

  return (await response.json()) as User;
}
