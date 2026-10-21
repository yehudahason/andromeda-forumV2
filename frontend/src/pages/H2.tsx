import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { User } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";
import { getMe } from "../lib/getMe";

export default function Home() {
  const navigate = useNavigate();

  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadSession() {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session) {
        navigate("/auth", { replace: true });
        return;
      }

      setUser(session.user);
      setLoading(false);
      console.log(await getMe());
    }

    loadSession();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        navigate("/auth", { replace: true });
        return;
      }

      setUser(session.user);
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [navigate]);

  async function handleLogout() {
    await supabase.auth.signOut();

    navigate("/auth", { replace: true });
  }

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-950 text-white">
        טוען...
      </div>
    );
  }

  return (
    <div
      dir="rtl"
      className="flex min-h-screen items-center justify-center bg-slate-950 px-4"
    >
      <div className="w-full max-w-lg rounded-2xl bg-slate-900 p-8 text-white shadow-xl">
        <h1 className="mb-6 text-3xl font-bold">שלום 👋</h1>

        <div className="space-y-3 text-slate-300">
          <p>
            <span className="font-semibold text-white">Email:</span>{" "}
            {user?.email}
          </p>

          <p>
            <span className="font-semibold text-white">User ID:</span>{" "}
            <span className="break-all" dir="ltr">
              {user?.id}
            </span>
          </p>

          <p>
            <span className="font-semibold text-white">Provider:</span>{" "}
            {user?.app_metadata.provider}
          </p>
        </div>

        <button
          type="button"
          onClick={handleLogout}
          className="mt-8 w-full rounded-lg bg-red-500 px-4 py-3 font-semibold text-white transition hover:bg-red-400"
        >
          התנתק
        </button>
      </div>
    </div>
  );
}
