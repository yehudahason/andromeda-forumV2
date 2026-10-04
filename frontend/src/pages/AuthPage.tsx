import { type SubmitEvent, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "../lib/supabase";

type Mode = "login" | "signup";

export default function AuthPage() {
  const navigate = useNavigate();

  const [mode, setMode] = useState<Mode>("login");
  const [email, setEmail] = useState("");
  const [name, setName] = useState("");
  const [password, setPassword] = useState("");

  const [loading, setLoading] = useState(false);
  const [checkingSession, setCheckingSession] = useState(true);

  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  useEffect(() => {
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      console.log("Auth event:", event);

      // Supabase sends INITIAL_SESSION when it finishes loading
      // the existing session from browser storage.
      if (event === "INITIAL_SESSION") {
        setCheckingSession(false);
      }

      // Existing login, email verification return,
      // Google OAuth return, normal login, etc.
      if (session) {
        navigate("/", { replace: true });
      }
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [navigate]);

  async function handleSubmit(e: SubmitEvent<HTMLFormElement>) {
    e.preventDefault();

    setLoading(true);
    setError("");
    setMessage("");

    try {
      if (mode === "signup") {
        const { data, error } = await supabase.auth.signUp({
          email,
          password,

          options: {
            data: {
              name: name.trim(),
            },
            // User returns here after clicking verification email.
            emailRedirectTo: `${window.location.origin}/auth`,
          },
        });

        if (error) {
          throw error;
        }

        // If email confirmation is disabled,
        // Supabase may return a session immediately.
        if (data.session) {
          navigate("/", { replace: true });
          return;
        }

        setMessage(
          "Account created. Check your email and click the verification link.",
        );
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email,
          password,
        });

        if (error) {
          throw error;
        }

        // No navigate() needed here.
        // onAuthStateChange() receives SIGNED_IN and redirects.
      }
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Something went wrong. Please try again.",
      );
    } finally {
      setLoading(false);
    }
  }

  async function handleGoogleLogin() {
    setLoading(true);
    setError("");
    setMessage("");

    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",

      options: {
        redirectTo: `${window.location.origin}/auth`,
      },
    });

    if (error) {
      setError(error.message);
      setLoading(false);
    }

    // If successful, Supabase redirects the browser to Google.
  }

  if (checkingSession) {
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
      <div className="w-full max-w-md rounded-2xl bg-slate-900 p-8 shadow-xl">
        <h1 className="mb-2 text-center text-3xl font-bold text-white">
          {mode === "login" ? "התחברות" : "הרשמה"}
        </h1>

        <p className="mb-8 text-center text-sm text-slate-400">
          {mode === "login" ? "התחבר לחשבון שלך" : "צור חשבון חדש"}
        </p>

        {error && (
          <div className="mb-5 rounded-lg border border-red-500/30 bg-red-500/10 p-3 text-sm text-red-400">
            {error}
          </div>
        )}

        {message && (
          <div className="mb-5 rounded-lg border border-green-500/30 bg-green-500/10 p-3 text-sm text-green-400">
            {message}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          {mode === "signup" && (
            <div>
              <label
                htmlFor="name"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                שם משתמש
              </label>

              <input
                id="name"
                type="name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
                className="w-full rounded-lg border border-slate-700 bg-slate-800 px-4 py-3 text-white outline-none transition focus:border-cyan-400"
              />
            </div>
          )}
          <div>
            <label
              htmlFor="email"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              אימייל
            </label>

            <input
              id="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              dir="ltr"
              placeholder="you@example.com"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-4 py-3 text-white outline-none transition focus:border-cyan-400"
            />
          </div>

          <div>
            <label
              htmlFor="password"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              סיסמה
            </label>

            <input
              id="password"
              type="password"
              autoComplete={
                mode === "login" ? "current-password" : "new-password"
              }
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              dir="ltr"
              className="w-full rounded-lg border border-slate-700 bg-slate-800 px-4 py-3 text-white outline-none transition focus:border-cyan-400"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg bg-cyan-500 px-4 py-3 font-semibold text-slate-950 transition hover:bg-cyan-400 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {loading ? "טוען..." : mode === "login" ? "התחבר" : "הרשם"}
          </button>
        </form>

        <div className="my-6 flex items-center gap-3">
          <div className="h-px flex-1 bg-slate-700" />

          <span className="text-sm text-slate-500">או</span>

          <div className="h-px flex-1 bg-slate-700" />
        </div>

        <button
          type="button"
          onClick={handleGoogleLogin}
          disabled={loading}
          className="flex w-full items-center justify-center gap-3 rounded-lg border border-slate-700 bg-white px-4 py-3 font-medium text-slate-900 transition hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-50"
        >
          <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden="true">
            <path
              fill="#4285F4"
              d="M21.6 12.23c0-.71-.06-1.4-.18-2.07H12v3.92h5.38a4.6 4.6 0 0 1-2 3.02v2.54h3.24c1.9-1.75 2.98-4.33 2.98-7.41Z"
            />

            <path
              fill="#34A853"
              d="M12 22c2.7 0 4.97-.9 6.63-2.42l-3.24-2.52c-.9.6-2.05.95-3.39.95-2.61 0-4.82-1.76-5.61-4.13H3.04v2.6A10 10 0 0 0 12 22Z"
            />

            <path
              fill="#FBBC05"
              d="M6.39 13.88A6 6 0 0 1 6.07 12c0-.65.11-1.28.32-1.88V7.52H3.04A10 10 0 0 0 2 12c0 1.61.39 3.14 1.04 4.48l3.35-2.6Z"
            />

            <path
              fill="#EA4335"
              d="M12 5.99c1.47 0 2.78.5 3.82 1.5l2.87-2.87C16.96 3.01 14.7 2 12 2a10 10 0 0 0-8.96 5.52l3.35 2.6C7.18 7.75 9.39 5.99 12 5.99Z"
            />
          </svg>
          המשך עם Google
        </button>

        <div className="mt-8 text-center text-sm text-slate-400">
          {mode === "login" ? "עדיין אין לך חשבון?" : "כבר יש לך חשבון?"}

          <button
            type="button"
            onClick={() => {
              setMode((current) => (current === "login" ? "signup" : "login"));

              setError("");
              setMessage("");
            }}
            className="mr-2 font-medium text-cyan-400 hover:text-cyan-300"
          >
            {mode === "login" ? "הרשם" : "התחבר"}
          </button>
        </div>
      </div>
    </div>
  );
}
