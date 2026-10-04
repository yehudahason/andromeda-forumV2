import { Routes, Route } from "react-router-dom";
import Home from "./pages/Home";
import About from "./pages/About";
import NotFound from "./pages/NotFound";
import ForumPage from "./pages/ForumPage";
import ThreadPage from "./pages/ThreadPage";
import NewThread from "./pages/NewThread";
import NewReply from "./pages/NewReply";
// import AuthGuard from "./components/Guard";
import UploadPage from "./pages/UploadPage";
import EditThread from "./pages/EditThread";
import EditReply from "./pages/EditReply";
import NewPosts from "./pages/NewPosts";
import { useEffect } from "react";
import { useUserStore } from "./stores/userStore";
import { supabase } from "./lib/supabase";
// import { useNavigate } from "react-router-dom";

import { getMe } from "./lib/getMe";
import AuthPage from "./pages/AuthPage";

export default function App() {
  // const navigate = useNavigate();
  const setUser = useUserStore((state) => state.setUser);
  useEffect(() => {
    async function loadSession() {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session) {
        // navigate("/auth", { replace: true });
        console.log("No session");
        return;
      }

      await setMe();
      console.log(await getMe());
    }

    loadSession();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!session) {
        // navigate("/auth", { replace: true });
        console.log("No session");
        return;
      }
      setMe();
    });
    async function setMe() {
      setUser(await getMe());
    }
    return () => {
      subscription.unsubscribe();
    };
  }, [setUser]);

  useEffect(() => {
    async function loadUser() {
      try {
        const result = await getMe();
        console.log("getMe:", result);

        if (result) {
          setUser(result);
        } else {
          setUser(null);
        }
      } catch (error) {
        console.error("loadUser:", error);
        setUser(null);
      }
    }

    loadUser();
  }, [setUser]);
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/auth" element={<AuthPage />} />
      <Route path="/forum/:f" element={<ForumPage />} />
      <Route path="/newposts" element={<NewPosts />} />
      <Route path="/forum/:f/:t" element={<ThreadPage />} />
      <Route
        path="/post/:f"
        element={
          // <AuthGuard>
          <NewThread />
          // </AuthGuard>
        }
      />
      <Route
        path="/editThread/:f/:t"
        element={
          // <AuthGuard>
          <EditThread />
          // </AuthGuard>
        }
      />
      <Route
        path="/post/:f/:t"
        element={
          // <AuthGuard>
          <NewReply />
          // </AuthGuard>
        }
      />
      <Route
        path="/editReply/:f/:t/:id"
        element={
          // <AuthGuard>
          <EditReply />
          // </AuthGuard>
        }
      />
      <Route path="/about" element={<About />} />
      <Route path="/upload" element={<UploadPage />} />

      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}
