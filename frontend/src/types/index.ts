import { type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";

export type UserProfile = {
  id: string;
  name: string;
  account_type: string;
};

export type AuthContextType = {
  session: Session | null | undefined;
  users: UserProfile[];

  signUpNewUser: (
    email: string,
    password: string,
    accountType: string,
    name: string,
  ) => Promise<{
    success: boolean;
    data?: unknown;
    error?: string;
  }>;

  signInUser: (
    email: string,
    password: string,
  ) => Promise<{
    success: boolean;
    data?: unknown;
    error?: string;
  }>;

  signOut: () => Promise<{
    success: boolean;
    error?: string;
  }>;
};

export type AuthProviderProps = {
  children: ReactNode;
};
export interface TodoItem {
  id: number;
  text: string;
  completed: boolean;
}

// The type for your array would be:
export type TodoList = TodoItem[];

export type FilterType = "all" | "active" | "completed";
