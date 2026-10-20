import getToken from "../../lib/getToken";

const API_URL = "https://api.pitron-halomot.org";

type PrivateRequestOptions = {
  method?: "GET" | "POST" | "PUT" | "DELETE";
  body?: unknown;
  signal?: AbortSignal;
};

export async function privateRequest<T>(
  path: string,
  { method = "GET", body, signal }: PrivateRequestOptions = {},
): Promise<T> {
  const token = await getToken();
  if (!token) {
    throw new Error("You must be logged in to use private messages");
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
  };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
  }

  const response = await fetch(`${API_URL}${path}`, {
    method,
    headers,
    signal,
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });

  if (!response.ok) {
    const message = (await response.text()).trim();
    throw new Error(message || `Private API request failed (${response.status})`);
  }

  // DELETE /api/private/messages/{id} returns HTTP 204, not JSON.
  if (response.status === 204) {
    return undefined as T;
  }
  return (await response.json()) as T;
}

