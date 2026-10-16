import getToken from "../lib/getToken";

export async function followThread(threadID: number) {
  let token;
  const url = "https://api.pitron-halomot.org";
  try {
    token = await getToken();
  } catch (e) {
    console.log(e);
    return "error processing token";
  }
  const response = await fetch(`${url}/api/threads/${threadID}/follow`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  if (!response.ok) {
    throw new Error("Failed to follow thread");
  }
}
