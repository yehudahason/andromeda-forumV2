import { useEffect, useState, useCallback } from "react";
import { Link } from "react-router-dom";
import { getMe } from "../lib/getMe.ts";
import { GetAvatar } from "../utils/GetAvatar.tsx";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { useUserStore } from "../stores/userStore";
import { useSessionStore } from "../stores/sessionStore";
import { supabase } from "../lib/supabase.ts";
import { getNotifications } from "../fetchMethods/privateMessages/notificationFuncs.ts";
import { useQueryClient } from "@tanstack/react-query";
import { markAllNotificationsRead } from "../fetchMethods/privateMessages/notificationFuncs.ts";
import { markNotificationRead } from "../fetchMethods/privateMessages/notificationFuncs.ts";
import { formatDate } from "../utils/formatDate.ts";
export default function Header() {
  const [tzurMenu, setTzurMenu] = useState<boolean>(false);
  const [notiMenu, setNotiMenu] = useState<boolean>(false);
  const [mailMenu, setMailMenu] = useState<boolean>(false);
  const [isMenu, setIsMenu] = useState<boolean>(false);

  const baseUrl = import.meta.env.BASE_URL;
  const { user, setUser } = useUserStore((state) => state);
  const { setSession } = useSessionStore((state) => state);
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const handleSignOut = async () => {
    console.log("1. sign out clicked");

    try {
      await supabase.auth.signOut();

      setUser(null);
      setSession(null);

      console.log("4. signed out");
    } catch (error) {
      console.error("5. signOut exception:", error);
    }
  };

  async function getUser() {
    try {
      const res = await getMe();
      console.log(res);
      return res;
    } catch (error) {
      console.log(error);
    }
  }
  //Getting Notifications
  const { data, isLoading, error } = useQuery({
    queryKey: ["notifications"],
    queryFn: ({ signal }) => getNotifications(1, signal),
    refetchInterval: 60 * 1000,
  });
  //To refetch notifications after update
  const refreshNotifications = useCallback(async () => {
    await queryClient.invalidateQueries({
      queryKey: ["notifications"],
    });
  }, [queryClient]);
  console.log(data);

  useEffect(() => {
    refreshNotifications();
  }, [notiMenu, mailMenu, refreshNotifications]);
  const threadsNotification = data?.notifications
    ? data?.notifications.filter((item) => item.type === "thread_reply")
    : [];
  const pMessagesNotification = data?.notifications
    ? data?.notifications.filter((item) => item.type === "private_message")
    : [];

  const tNotReadLength = threadsNotification?.filter(
    (item) => !item.is_read,
  ).length;
  const pmNotReadLength = pMessagesNotification?.filter(
    (item) => !item.is_read,
  ).length;

  if (isLoading) console.log("Loading:", isLoading);
  if (error) console.log("Erorr fetching notifications:", error);
  return (
    <div className="flex flex-col">
      <header className="bg-black w-full h-20">
        <div className="mx-auto max-w-[1280px] px-4 w-full justify-between flex flex-row items-center ">
          <a href="/" className="h-20">
            <img
              className="h-full sm:w-full w-[15rem] object-cover"
              src={`${baseUrl}pm.png`}
              alt=""
            />
          </a>
          {user ? (
            <>
              <img
                className="md:hidden block"
                src={`${baseUrl}account.png`}
                alt=""
              />

              <ul className="md:flex  hidden items-center h-18 py-8  flex-row justify-end ">
                <li className="group relative flex  border-l border-l-blue-200 px-3 text-white">
                  <button
                    onClick={() => {
                      setIsMenu(false);
                      setNotiMenu(false);
                      setMailMenu(false);
                      setTzurMenu(!tzurMenu);
                      getUser();
                    }}
                    className="cursor-pointer flex items-center gap-1"
                  >
                    <img src={`${baseUrl}add.png`} alt="" />
                    <span>צור</span>
                  </button>

                  <ul
                    className={`${tzurMenu ? "visible opacity-100" : "opacity-0 invisible"}
       absolute right-[-65%] top-[140%] z-50
      w-62 rounded-md bg-neutral-600
       text-right  shadow-lg
      transition
      
  `}
                  >
                    {/* Triangle */}
                    <div
                      className="
        absolute -top-2 right-1/3 translate-x-1/4
        border-l-8 border-r-8 border-b-8
        border-l-transparent border-r-transparent
        border-b-neutral-600
      "
                    />

                    <li>
                      <a
                        href="#"
                        className="block  p-2 rounded-md text-white hover:bg-neutral-500"
                      >
                        נושא חדש
                      </a>
                    </li>

                    <li>
                      <a
                        href="#"
                        className="block  rounded-md p-2 text-white hover:bg-neutral-500"
                      >
                        קובץ להורדה
                      </a>
                    </li>
                  </ul>
                </li>
                <li className="px-2 relative flex justify-center items-center">
                  {tNotReadLength && (
                    <span className="bg-sky-500 px-1.5 py-0 text-white  absolute -top-4 right-1 rounded-full">
                      {tNotReadLength}
                    </span>
                  )}
                  <button
                    onClick={() => {
                      setIsMenu(false);
                      setTzurMenu(false);
                      setMailMenu(false);
                      setNotiMenu(!notiMenu);
                    }}
                  >
                    <img src={`${baseUrl}notifications.png`} alt="" />
                  </button>

                  <ul
                    className={`${notiMenu ? "visible opacity-100" : "opacity-0 invisible"}
       absolute -left-41 top-[140%] z-50
      w-92 rounded-md bg-neutral-600
       text-right  shadow-lg
      transition 
      
  `}
                  >
                    {/* Triangle */}
                    <div
                      className="
        absolute -top-2 right-1/2 translate-x-1/2
        border-l-8 border-r-8 border-b-8
        border-l-transparent border-r-transparent
        border-b-neutral-600
      "
                    />

                    <li
                      className="flex justify-between items-center px-4 py-6
                border-b border-b-gray-400
                "
                    >
                      <h3 className="text-white ">התראות אחרונות</h3>
                      <button
                        onClick={async () => {
                          await markAllNotificationsRead();
                          await refreshNotifications();
                        }}
                        className="text-sky-400
                  flex justify-center items-center gap-2
                  active:scale-[0.94] transition-transform duration-150"
                      >
                        <img src={`${baseUrl}settings_sky.png`} alt="" />
                        סמן הכל כנקרא
                      </button>
                    </li>
                    {threadsNotification?.map((item) => {
                      if (item.type === "thread_reply" && !item.is_read)
                        return (
                          <li key={item.id} className="text-white">
                            <a
                              href={`/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}#${item.reply_id}`}
                              onClick={async (e) => {
                                e.preventDefault();

                                await markNotificationRead(item.id);
                                await refreshNotifications();
                                window.location.href = `/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}#${item.reply_id}`;
                                setIsMenu(false);
                                setNotiMenu(false);
                                setMailMenu(false);
                                setTzurMenu(false);
                              }}
                            >
                              <span className="flex items-center gap-4">
                                <span>{formatDate(item.created_at)}</span>
                                <span className="truncate">
                                  {item.actor_name} הגיב בדיון-{" "}
                                  {item.thread_title}
                                </span>
                              </span>
                            </a>
                          </li>
                        );
                    })}
                    {tNotReadLength === 0 && (
                      <li className="border-b border-b-gray-400 px-4 py-6 text-white text-center ">
                        אין התראות להצגה
                      </li>
                    )}
                    <li className="flex flex-row justify-center items-center text-sky-400 px-4 py-6">
                      <a
                        href="/notification"
                        className=" flex flex-row justify-center items-center rounded-md gap-2 hover:bg-neutral-500"
                      >
                        <img src={`${baseUrl}menu_sky.png`} alt="" />
                        צפה בכל ההתראות
                      </a>
                    </li>
                  </ul>
                </li>

                <li className="px-2 border-l border-l-blue-200  relative flex justify-center items-center">
                  {pmNotReadLength && (
                    <span className="bg-amber-200 px-1.5 py-0 text-amber-900  absolute -top-4 right-1 rounded-full">
                      {pmNotReadLength}
                    </span>
                  )}
                  <button
                    onClick={() => {
                      setIsMenu(false);
                      setNotiMenu(false);
                      setTzurMenu(false);
                      setMailMenu(!mailMenu);
                    }}
                  >
                    <img src={`${baseUrl}mail.png`} alt="" />
                  </button>

                  <ul
                    className={`${mailMenu ? "visible opacity-100" : "opacity-0 invisible"}
       absolute -left-40 top-[140%] z-50
      w-92 rounded-md bg-neutral-600
       text-right  shadow-lg
      transition 
      
  `}
                  >
                    {/* Triangle */}
                    <div
                      className="
        absolute -top-2 right-1/2 translate-x-1/2
        border-l-8 border-r-8 border-b-8
        border-l-transparent border-r-transparent
        border-b-neutral-600
      "
                    />

                    <li
                      className="flex justify-between items-center px-4 py-6
                border-b border-b-gray-400
                "
                    >
                      <h3 className="text-white font-semibold ">
                        הודעות פרטיות
                      </h3>
                      <a
                        href=""
                        className="bg-sky-400 px-2 py-1 rounded-lg text-black
                  flex justify-center items-center gap-2
                  "
                      >
                        צור הודעה פרטית חדשה
                      </a>
                    </li>

                    {pMessagesNotification?.map((item) => {
                      if (item.type === "private_message" && !item.is_read)
                        return (
                          <li key={item.id} className="text-white">
                            <a
                              href={`/private/${item.private_thread_id}/?page=${item.thread_page}#${item.message_id}`}
                              onClick={async (e) => {
                                e.preventDefault();

                                await markNotificationRead(item.id);
                                await refreshNotifications();

                                window.location.href = `/private/${item.private_thread_id}/?page=${item.thread_page}#${item.message_id}`;
                                setIsMenu(false);
                                setNotiMenu(false);
                                setMailMenu(false);
                                setTzurMenu(false);
                              }}
                            >
                              <span className="flex items-center gap-4">
                                <span>{formatDate(item.created_at)}-</span>
                                <span>קיבלת הודעה מ-{item.actor_name}</span>
                              </span>
                            </a>
                          </li>
                        );
                    })}
                    {pmNotReadLength === 0 && (
                      <li className="border-b border-b-gray-400 px-4 py-6 text-white text-center ">
                        אין הודעות פרטיות להציג
                      </li>
                    )}

                    <li className="flex flex-row justify-center items-center text-sky-400 px-4 py-6">
                      <a
                        href="/inbox"
                        className=" flex flex-row justify-center items-center rounded-md gap-2 hover:bg-neutral-500"
                      >
                        <img src={`${baseUrl}menu_sky.png`} alt="" />
                        לך לתיבת ההודעות
                      </a>
                    </li>
                  </ul>
                </li>

                <li className="px-2 flex items-center gap-2 text-white relative">
                  {user &&
                    GetAvatar({
                      name: user.name,
                      image: user.image,
                      size: 32,
                    })}
                  <span className="flex  truncate">
                    <button
                      className="flex cursor-pointer"
                      onClick={() => {
                        setIsMenu(!isMenu);
                        setMailMenu(false);
                        setNotiMenu(false);
                        setTzurMenu(false);
                      }}
                    >
                      {" "}
                      {user?.name}
                      <img src={`${baseUrl}arrowdown.png`} alt="" />
                    </button>
                  </span>
                  <ul
                    className={`${isMenu ? "visible opacity-100" : "opacity-0 invisible"}
       absolute left-1 top-[140%] z-50
      w-fit rounded-md bg-neutral-600
       px-6 py-4 text-right  shadow-lg
      transition  flex flex-col gap-2
      
  `}
                  >
                    {user ? (
                      <>
                        <div
                          className="
        absolute -top-2 left-4
        border-l-8 border-r-8 border-b-8
        border-l-transparent border-r-transparent
        border-b-neutral-600
      "
                        />
                        <li>
                          <h3 className="text-center border-b border-b-blue-300">
                            Hello {user?.role}:
                          </h3>
                        </li>
                        <li>
                          <p className="border-b text-center border-b-blue-300">
                            {user?.name}
                          </p>
                        </li>
                        <li>
                          <button onClick={getUser}>GET session</button>
                        </li>
                        <li>
                          <button
                            onClick={handleSignOut}
                            className="w-fit rounded-lg bg-gray-900 px-4 p-2 font-medium text-white transition hover:bg-gray-800"
                          >
                            Sign Out
                          </button>
                        </li>
                      </>
                    ) : (
                      <p className="w-30 text-center">NOT SIGN IN</p>
                    )}
                  </ul>
                </li>
              </ul>
            </>
          ) : (
            <div className="flex gap-4 items-center">
              <button
                onClick={() => {
                  navigate("/auth?mode=signup");
                }}
                className="w-fit py-2 font-medium px-4 cursor-pointer rounded-lg text-amber-200"
              >
                צור חשבון
              </button>
              <button
                onClick={() => {
                  navigate("/auth?mode=login");
                }}
                className="w-fit py-2 font-medium px-4  cursor-pointer rounded-lg bg-sky-400"
              >
                התחבר
              </button>
            </div>
          )}
        </div>
      </header>
      <nav className="flex justify-center gap-4 bg-neutral-600 h-12 p-2 w-full">
        <div className="flex max-w-[1280px]  p-4 flex-row justify-between w-full items-center">
          <img
            className="sm:hidden block"
            src={`${baseUrl}menu_sky.png`}
            alt=""
          />
          <ul className="sm:flex hidden items-center gap-4 text-lg font-medium text-white">
            <li>
              <Link to="/">פורומים</Link>
            </li>
            <li>
              <a href="/newposts">מה חדש ?</a>
            </li>
            <li>בלוגים</li>
            <li>אודות</li>
          </ul>
          <img
            className="md:hidden block"
            src={`${baseUrl}search.png`}
            alt=""
          />
          <div className="md:flex hidden">
            <form className="relative w-full max-w-md">
              <input
                type="search"
                placeholder="חיפוש..."
                dir="rtl"
                className="
      h-8 w-full rounded-full
      bg-white
      px-5 pl-12
      text-right text-neutral-700
      outline-none
      placeholder:text-neutral-500
    "
              />

              <button
                type="submit"
                aria-label="חיפוש"
                className="
      absolute left-4 top-1/2
      -translate-y-1/2
      text-neutral-900
    "
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="3"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <circle cx="11" cy="11" r="7" />
                  <path d="m20 20-4-4" />
                </svg>
              </button>
            </form>
          </div>
        </div>
      </nav>
    </div>
  );
}
