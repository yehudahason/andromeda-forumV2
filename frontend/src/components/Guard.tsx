import { Navigate } from "react-router-dom";
import { useEffect } from "react";
import { loadSession } from "../lib/loadSession";
import { useSessionStore } from "../stores/sessionStore";

type Props = {
  children: React.ReactNode;
};

export default function AuthGuard({ children }: Props) {
  const session = useSessionStore((state) => state.session);
  const loading = useSessionStore((state) => state.loading);

  useEffect(() => {
    loadSession();
  }, []);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        Loading...
      </div>
    );
  }

  if (!session) {
    return <Navigate to="/" replace />;
  }

  return <>{children}</>;
}
