import { useState, useEffect, useRef, useCallback } from "react";
// import { authClient } from "./lib/auth.ts";
import { useSessionStore } from "./stores/sessionStore.ts";
import { useNavigate } from "react-router-dom";
import { useUserStore } from "./stores/userStore";
import Or from "./components/Or.tsx";
// import { getMe } from "./utils/getMe.ts";

type LoginProps = {
  setIsLogin: (value: boolean) => void;
  signUp: boolean;
};

export default function Login({ setIsLogin, signUp }: LoginProps) {
  const navigate = useNavigate();
  const { session, setSession } = useSessionStore((state) => state);
  const setUser = useUserStore((state) => state.setUser);

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isSignUp, setIsSignUp] = useState(signUp);
  const [openLogin, setOpenLogin] = useState(true);
  const [msg, setMsg] = useState<string | undefined>("");
  const [username, setUserName] = useState<string>("");

  const baseUrl = import.meta.env.BASE_URL;
  const menuRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);
  const handleClose = useCallback(() => {
    setOpenLogin(false);
    setIsLogin(false);
  }, [setIsLogin]);

  const handleGoogleLogin = async () => {
    await authClient.signIn.social({
      provider: "google",
      callbackURL: "/",
    });
    setUser(await getMe());
  };

  // Save current active element to restore focus when modal unmounts/closes
  useEffect(() => {
    previousFocusRef.current = document.activeElement as HTMLElement;
    return () => {
      previousFocusRef.current?.focus();
    };
  }, []);

  // Handle outside click & Keyboard navigation (Escape & Focus Trap)
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        handleClose();
      }
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (!openLogin) return;

      if (event.key === "Escape") {
        handleClose();
        return;
      }

      // Focus Trap Implementation
      if (event.key === "Tab" && menuRef.current) {
        const focusableElements = menuRef.current.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
        );
        const firstElement = focusableElements[0];
        const lastElement = focusableElements[focusableElements.length - 1];

        if (event.shiftKey && document.activeElement === firstElement) {
          event.preventDefault();
          lastElement?.focus();
        } else if (!event.shiftKey && document.activeElement === lastElement) {
          event.preventDefault();
          firstElement?.focus();
        }
      }
    }

    document.addEventListener("mousedown", handleClickOutside);
    document.addEventListener("keydown", handleKeyDown);

    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [openLogin, handleClose]);

  useEffect(() => {
    if (session) {
      navigate("/");
    }
  }, [session, navigate]);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setMsg("");

    try {
      if (isSignUp) {
        const result = await authClient.signUp.email({
          name: username || email.split("@")[0] || "User",
          email,
          password,
          callbackURL: "/",
        });

        if (result.error) {
          setMsg(result.error.message);
          return;
        }

        setMsg("Confirm email");
        return;
      }

      const result = await authClient.signIn.email({
        email,
        password,
      });

      if (result.error) {
        setMsg(result.error.message);
        return;
      }

      const sessionResult = await authClient.getSession();

      if (sessionResult.data?.session) {
        setSession(sessionResult.data.session);
        setUser(await getMe());
      }
    } catch (e) {
      if (e instanceof Error) {
        console.error(e);
        setMsg(e.message);
      }
    }
  };

  if (!openLogin) return null;

  return (
    <>
      {/* Backdrop overlay */}
      <div
        className="fixed inset-0 bg-black/40 z-40 transition-opacity"
        aria-hidden="true"
        onClick={handleClose}
      />

      <div
        ref={menuRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title"
        aria-describedby="modal-description"
        dir="rtl"
        tabIndex={-1}
        className="fixed left-1/2 top-1/2 z-50 w-full max-w-[87%] sm:max-w-md
          rounded-2xl bg-white p-6 shadow-lg
          -translate-x-1/2 -translate-y-1/2 transition-all duration-300 focus:outline-none"
      >
        <div className="text-center relative">
          <button
            type="button"
            onClick={handleClose}
            aria-label="סגור חלונית"
            className="absolute top-0 left-0 cursor-pointer p-1 rounded-md text-gray-400 hover:text-gray-700 focus:outline-none focus:ring-2 focus:ring-gray-900"
          >
            <img
              className="w-5 h-5"
              src={`${baseUrl}close.png`}
              alt=""
              aria-hidden="true"
            />
          </button>

          <h1
            id="modal-title"
            className="sm:text-3xl text-xl font-bold tracking-tight text-gray-900"
          >
            {isSignUp ? "צור חשבון" : "כניסה"}
          </h1>

          <p id="modal-description" className="mt-2 text-sm text-gray-500">
            {isSignUp ? "הרשם לפורום" : "הכנס לפורום"}
          </p>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-3 mt-4">
          {isSignUp && (
            <div>
              <label
                htmlFor="name"
                className="mb-1 block text-sm font-medium text-gray-700"
              >
                שם משתמש
              </label>

              <input
                id="name"
                type="text"
                placeholder="ישראל ישראלי"
                value={username}
                onChange={(e) => setUserName(e.target.value)}
                required
                aria-required="true"
                aria-invalid={msg ? "true" : "false"}
                aria-describedby={msg ? "auth-error-message" : undefined}
                className="w-full rounded-lg border border-gray-300 px-4 py-2.5 text-gray-900 outline-none transition placeholder:text-gray-400 focus:border-gray-900 focus:ring-2 focus:ring-gray-900/10"
              />
            </div>
          )}

          <div>
            <label
              htmlFor="email"
              className="mb-1 block text-sm font-medium text-gray-700"
            >
              כתובת אימייל
            </label>

            <input
              id="email"
              type="email"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              aria-required="true"
              aria-invalid={msg ? "true" : "false"}
              aria-describedby={msg ? "auth-error-message" : undefined}
              className="w-full rounded-lg border border-gray-300 px-4 py-2.5 text-gray-900 outline-none transition placeholder:text-gray-400 focus:border-gray-900 focus:ring-2 focus:ring-gray-900/10"
            />
          </div>

          <div>
            <label
              htmlFor="password"
              className="mb-1 block text-sm font-medium text-gray-700"
            >
              סיסמה
            </label>

            <input
              id="password"
              type="password"
              placeholder="••••••••"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              aria-required="true"
              aria-invalid={msg ? "true" : "false"}
              aria-describedby={msg ? "auth-error-message" : undefined}
              className="w-full rounded-lg border border-gray-300 px-4 py-2.5 text-gray-900 outline-none transition placeholder:text-gray-400 focus:border-gray-900 focus:ring-2 focus:ring-gray-900/10"
            />
          </div>

          <div
            aria-live="assertive"
            aria-atomic="true"
            className="min-h-[1.25rem]"
          >
            {msg && (
              <span
                id="auth-error-message"
                className="text-center block text-red-700 text-sm font-medium"
              >
                {msg}
              </span>
            )}
          </div>

          <button
            type="submit"
            className="cursor-pointer w-full rounded-lg bg-gray-900 px-4 py-2.5 font-semibold text-white transition hover:bg-gray-800 active:scale-[0.99] focus:outline-none focus:ring-2 focus:ring-gray-900 focus:ring-offset-2"
          >
            {isSignUp ? "צור חשבון" : "כניסה לרשומים"}
          </button>

          <button
            type="button"
            onClick={handleGoogleLogin}
            className="flex cursor-pointer w-full items-center justify-center gap-3 rounded-lg border border-gray-300 bg-white px-4 py-2.5 font-medium text-gray-700 transition hover:bg-gray-50 active:scale-[0.99] focus:outline-none focus:ring-2 focus:ring-gray-900 focus:ring-offset-2"
          >
            <span>המשך עם גוגל</span>
            <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden="true">
              <path
                fill="#4285F4"
                d="M21.35 12.23c0-.79-.07-1.55-.2-2.27H12v4.3h5.24a4.48 4.48 0 0 1-1.94 2.94v2.45h3.14c1.84-1.7 2.91-4.21 2.91-7.42Z"
              />
              <path
                fill="#34A853"
                d="M12 21.75c2.63 0 4.84-.87 6.46-2.35l-3.14-2.45c-.87.58-1.98.92-3.32.92-2.55 0-4.71-1.72-5.49-4.04H3.27v2.53A9.75 9.75 0 0 0 12 21.75Z"
              />
              <path
                fill="#FBBC05"
                d="M6.51 13.83A5.86 5.86 0 0 1 6.2 12c0-.64.11-1.26.31-1.83V7.64H3.27A9.75 9.75 0 0 0 2.25 12c0 1.57.38 3.05 1.02 4.36l3.24-2.53Z"
              />
              <path
                fill="#EA4335"
                d="M12 6.13c1.43 0 2.72.49 3.74 1.45l2.8-2.8C16.84 3.21 14.63 2.25 12 2.25a9.75 9.75 0 0 0-8.73 5.39l3.24 2.53C7.29 7.85 9.45 6.13 12 6.13Z"
              />
            </svg>
          </button>
        </form>

        <Or />

        <p className="mt-6 text-center text-sm text-gray-500">
          {isSignUp ? (
            <>
              יש לך כבר חשבון?{" "}
              <button
                type="button"
                onClick={() => setIsSignUp(false)}
                className="cursor-pointer font-semibold text-gray-900 hover:underline focus:outline-none focus:ring-2 focus:ring-gray-900 rounded px-1"
              >
                הכנס.
              </button>
            </>
          ) : (
            <>
              אין לך חשבון?{" "}
              <button
                type="button"
                onClick={() => setIsSignUp(true)}
                className="cursor-pointer font-semibold text-gray-900 hover:underline focus:outline-none focus:ring-2 focus:ring-gray-900 rounded px-1"
              >
                הרשם.
              </button>
            </>
          )}
        </p>
      </div>
    </>
  );
}
