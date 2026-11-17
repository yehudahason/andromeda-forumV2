import { useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { getNotifications } from "../fetchMethods/privateMessages/notificationFuncs";
import { useEffect, useMemo } from "react";
import Pagination from "../components/Paginatiom";
// import { GetAvatar } from "../utils/GetAvatar";
import { formatDate } from "../utils/formatDate";
import { markNotificationRead } from "../fetchMethods/privateMessages/notificationFuncs";

export default function AllNotification() {
  const [searchParams, setSearchParams] = useSearchParams();
  const queryClient = useQueryClient();

  // Read page from URL.
  const rawPage = Number(searchParams.get("page") ?? "1");

  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;
  // const queryClient = useQueryClient();
  const { data, isPending, isError, error } = useQuery({
    queryKey: ["notifications", page],
    queryFn: ({ signal }) => getNotifications(page, signal),
    refetchInterval: 10 * 60 * 1000,
  });
  //To refetch notifications after update
  const refreshNotifications = async () => {
    await queryClient.invalidateQueries({
      queryKey: ["notifications"],
    });
  };

  const notifications = useMemo(() => {
    return data?.notifications ?? [];
  }, [data]);

  const total = data?.total ?? 0;

  const totalPages = data?.total_pages ?? 1;

  function changePage(newPage: number) {
    if (newPage < 1 || newPage > totalPages) return;

    setSearchParams({ page: String(newPage) });
  }
  useEffect(() => {
    console.log("test:", notifications);
  }, [notifications]);
  if (isPending) {
    return (
      <div dir="rtl" className="mx-auto max-w-4xl p-6">
        <p className="text-gray-500">טוען הודעות פרטיות...</p>
      </div>
    );
  }

  if (isError) {
    return (
      <div dir="rtl" className="mx-auto max-w-4xl p-6">
        <p className="text-red-500">שגיאה בטעינת ההודעות: {error.message}</p>

        <button
          type="button"
          className="mt-4 rounded bg-blue-600 px-4 py-2 text-white"
        >
          נסה שוב
        </button>
      </div>
    );
  }

  return (
    <>
      <main dir="rtl" className="mx-auto max-w-4xl px-4 py-6">
        {totalPages && (
          <div className="flex h-fit items-center justify-between border-b  border-white/15 ">
            <Pagination
              total={total}
              currentPage={page}
              onPageChange={changePage}
            />
          </div>
        )}
        {/* Header */}

        <div>
          <h1 className="text-2xl py-4 text-white font-bold">כל ההתראות</h1>
        </div>
        <ul>
          {notifications.map((item) => {
            if (item.type === "thread_reply")
              return (
                <li className="text-white">
                  <a
                    href={`/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}#${item.reply_id}`}
                    onClick={async (e) => {
                      e.preventDefault();

                      await markNotificationRead(item.id);
                      await refreshNotifications();
                      window.location.href = `/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}#${item.reply_id}`;
                    }}
                  >
                    <span className="flex items-center gap-4">
                      <span>{formatDate(item.created_at)}-</span>
                      <span className="truncate">
                        תגובה בדיון - {item.thread_title}
                      </span>
                    </span>
                  </a>
                </li>
              );
            else {
              return (
                <li className="text-white">
                  <a
                    href={`/private/${item.private_thread_id}/?page=${item.thread_page}#${item.message_id}`}
                    onClick={async (e) => {
                      e.preventDefault();
                      await markNotificationRead(item.id);
                      await refreshNotifications();

                      window.location.href = `/private/${item.private_thread_id}/?page=${item.thread_page}#${item.message_id}`;
                    }}
                  >
                    {" "}
                    <span className="flex items-center gap-4">
                      <span>{formatDate(item.created_at)}-</span>
                      <span>קיבלת הודעה מ-{item.actor_name}</span>
                    </span>
                  </a>
                </li>
              );
            }
          })}
        </ul>
        {totalPages > 1 && (
          <div className="flex h-fit items-center justify-between border-b  border-white/15 ">
            <Pagination
              total={total}
              currentPage={page}
              onPageChange={changePage}
            />
          </div>
        )}
      </main>
    </>
  );
}
