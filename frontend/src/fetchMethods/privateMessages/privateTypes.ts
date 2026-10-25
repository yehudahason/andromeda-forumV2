export type PrivateThread = {
  id: number;
  title: string | null;
  created_by: string | null;
  last_message_at: string | null;
  created_at: string;
  updated_at: string;
};

export interface PrivateThreadSummary {
  id: number;
  title: string | null;
  created_by: string | null;
  created_by_name: string | null;
  last_message_at: string | null;
  created_at: string;
  updated_at: string;
  participants_count: number;
  unread_count: number;
  last_message_content?: string | null;
  last_message_sender_id?: string | null;
}

export interface PrivateThreadListResponse {
  threads: PrivateThreadSummary[];
  total: number;
  page: number;
  per_page: number;
}

export type PrivateParticipant = {
  user_id: string;
  joined_at: string;
  last_read_at: string | null;
};

export type PrivateMessage = {
  id: number;
  thread_id: number;
  sender_id: string | null;
  sender_name: string;
  content: string;
  created_at: string;
  updated_at: string;
};

export type PrivatePaginated<T, K extends string> = {
  total: number;
  page: number;
  per_page: number;
} & Record<K, T[]>;

export type PrivateMessagesResponse = PrivatePaginated<
  PrivateMessage,
  "messages"
>;

export type CreatePrivateThreadInput = {
  title?: string;
  participant_ids: string[];
  content: string; // First message
};

export type CreatePrivateThreadResponse = {
  thread: PrivateThread;
  message: PrivateMessage;
  participant_ids: string[];
};

export type PrivateThreadDetailsResponse = {
  thread: PrivateThread;
  participants: PrivateParticipant[];
};

export type PrivateThreadReadResponse = {
  thread_id: number;
  last_read_at: string;
};
