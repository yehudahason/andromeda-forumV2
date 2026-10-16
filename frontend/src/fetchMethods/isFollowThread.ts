import getToken from "../lib/getToken";

export async function isFollowThread(threadID: number): Promise<boolean> {
  const url = "https://api.pitron-halomot.org";

  const token = await getToken();

  const response = await fetch(`${url}/api/threads/${threadID}/follow`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    throw new Error("Failed to check thread follow status");
  }

  const data: { following: boolean } = await response.json();

  return data.following;
}
