export type UserThread = {
  id: number;
  forum_id: number;
  forum_name: string;
  title: string;
  views: number;
  messages_count: number;
  sticky: boolean;
  created_at: string;
};

export type UserThreadsResponse = {
  threads: UserThread[];
  page: number;
  total_pages: number;
  total: number;
  has_next: boolean;
};
export async function getUserThreads(
  userId: string,
  page = 1,
  signal?: AbortSignal,
): Promise<UserThreadsResponse> {
  const url = "https://api.pitron-halomot.org";

  const response = await fetch(
    `${url}/api/users/${userId}/threads?page=${page}`,
    {
      method: "GET",
      signal,
    },
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch threads: ${response.status}`);
  }

  return response.json();
}
