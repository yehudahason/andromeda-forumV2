import getToken from "./getToken";
export async function getMe(signal?: AbortSignal) {
  let token = null;
  try {
    token = await getToken();
  } catch (e) {
    if (e instanceof Error) console.log(e.message);
  }
  if (!token) return null;
  const url = "https://api.pitron-halomot.org";
  try {
    const res = await fetch(`${url}/api/me`, {
      headers: {
        Authorization: `Bearer ${token}`,
      },
      signal,
    });

    if (!res.ok) {
      throw new Error(`Failed to fetch user: ${res.status}`);
    }
    if (res.status === 401) {
      console.log("Not Authenticated - 401");
      return null;
    }
    return await res.json();
  } catch (e) {
    if (e instanceof Error) {
      console.error("getMe:", e.message);
    }

    return null;
  }
}
