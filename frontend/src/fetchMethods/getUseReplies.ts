export type UserReply = {
  id: string;
  post: string;
  forum_id: number;
  forum_name: string;
  thread_id: number;
  thread_title: string;
  thread_page: string;
  created_at: string;
};

export type UserRepliesResponse = {
  replies: UserReply[];
  page: number;
  total_pages: number;
  total: number;
  has_next: boolean;
};
export async function getUserReplies(
  userId: string,
  page = 1,
  signal?: AbortSignal,
): Promise<UserRepliesResponse> {
  const url = "https://api.pitron-halomot.org";

  const response = await fetch(
    `${url}/api/users/${userId}/replies?page=${page}`,
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
