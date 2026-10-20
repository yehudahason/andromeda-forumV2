export type PrivateThread = {
  id: number;
  title: string | null;
  created_by: string | null;
  last_message_at: string | null;
  created_at: string;
  updated_at: string;
};

export type PrivateThreadSummary = PrivateThread & {
  participants_count: number;
  unread_count: number;
};

export type PrivateParticipant = {
  user_id: string;
  joined_at: string;
  last_read_at: string | null;
};

export type PrivateMessage = {
  id: number;
  thread_id: number;
  sender_id: string | null;
  content: string;
  created_at: string;
  updated_at: string;
};

export type PrivatePaginated<T, K extends string> = {
  total: number;
  page: number;
  per_page: number;
} & Record<K, T[]>;

export type PrivateThreadListResponse = PrivatePaginated<
  PrivateThreadSummary,
  "threads"
>;
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
