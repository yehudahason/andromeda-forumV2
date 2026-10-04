import { supabase } from "./supabase";

export default async function getToken() {
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    console.log("Not Authenticated");
    return;
  }
  const token = session?.access_token;

  return token;
}
