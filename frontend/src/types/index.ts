export interface TodoItem {
  id: number;
  text: string;
  completed: boolean;
}

// The type for your array would be:
export type TodoList = TodoItem[];

export type FilterType = "all" | "active" | "completed";

export type ThreadType = {
  id: number;
  forum_id: number;
  title: string;
  author: string | null;
  messages_count: number;
  last_post_title: string | null;
  last_post_author: string | null;
  last_post_date: string | null;
  created_at: string;
};

export type ForumType = {
  id: string;
  name: string;
  sort_order: number;
  description: string;
  messages_count: number;
  last_post_title: string | null;
  last_post_author: string | null;
  last_post_date: string | null;
  image: string | null;
  last_post_thread_id: string | null;
};

export type Users = User[];

export type ReplyType = {
  id: string;
  thread_id: number;
  title: string;
  author: User;
  post: string;
  created_at: string;
  updated_at: string;
};

export type ReplyListResponse = {
  replies: ReplyType[];
  total: number;
  page: number;
  per_page: number;
};

export type ThreadDetails = {
  id: number;
  forum_name: string;
  forum_id: number;
  author: User;
  title: string;
  content: string;
  created_at: string;
};

export type User = {
  id: string;
  name: string;
  email: string | null;
  image: string | null;
  replies_count: number;
  created_at: string;
  role: string;
};

export type CreateThreadResponse = {
  id: number;
  forum_id: number;
  user_id: string;
  title: string;
  content: string;
  notify: boolean;
  created_at: string;
} | null;

export type ReplyPost = {
  id: string;
  post: string;
  notify: boolean;
};

export type LatestPost = {
  id: string;
  post_type: string;
  thread_id: number;
  forum_id: number;
  forum_name: string;

  open_user_id: string;
  open_user_name: string;
  open_user_image: string;

  last_reply_user_id: string | null;
  last_reply_user_name: string;

  thread_title: string;
  thread_content: string;
  last_reply_content: string;
  created_at: string;
  messages_count: number;
};
