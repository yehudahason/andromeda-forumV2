import { getAuthToken } from "../lib/getAuthToken";

export async function deleteReply(id: string, signal?: AbortSignal) {
  let token;
  const url = "https://api.pitron-halomot.org";
  try {
    token = await getAuthToken();
  } catch (e) {
    console.log(e);
    return "error processing token";
  }
  const response = await fetch(`${url}/api/replies/${id}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${token}`,
    },
    signal,
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(error || "Failed to delete thread");
  }
}
