import { Link, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { formatDateFull } from "../utils/formatDateFull";
import { getPrivateThreads } from "../fetchMethods/privateMessages/getPrivateThreads";
import { useEffect, useMemo } from "react";
// import type { PrivateThread } from "../types/index";
import Pagination from "../components/Paginatiom";

function stripHTML(html: string): string {
  const doc = new DOMParser().parseFromString(html, "text/html");
  return doc.body.textContent ?? "";
}

export default function PrivateInbox() {
  const [searchParams, setSearchParams] = useSearchParams();

  // Read page from URL.
  const rawPage = Number(searchParams.get("page") ?? "1");

  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;

  const { data, isPending, isError, error, refetch } = useQuery({
    queryKey: ["privateThreads", page],

    queryFn: ({ signal }) => getPrivateThreads(page, signal),

    staleTime: 10_000,
    refetchInterval: 15_000,
    refetchOnWindowFocus: true,
  });

  // Your Go backend returns:
  // { threads, total, page, per_page }

  const threads = useMemo(() => {
    return data?.threads ?? [];
  }, [data]);

  const total = data?.total ?? 0;
  const perPage = data?.per_page ?? 14;

  const totalPages = Math.ceil(total / perPage);

  // Backend already orders threads by most recent activity.
  const sortedThreads = threads;

  // Total unread messages on the current page.
  const unreadCount = threads.reduce(
    (sum, thread) => sum + thread.unread_count,
    0,
  );

  function changePage(newPage: number) {
    if (newPage < 1 || newPage > totalPages) return;

    setSearchParams({ page: String(newPage) });
  }
  useEffect(() => {
    console.log(threads);
  }, [threads]);
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
          onClick={() => void refetch()}
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
        <div className="mb-6 flex items-center justify-between">
          <div>
            <h1 className="text-2xl py-4 text-white font-bold">
              הודעות פרטיות
            </h1>

            <p className="mt-1 text-sm text-gray-500">
              {total} שיחות
              {unreadCount > 0 && (
                <span className="mr-2 text-blue-600">
                  • {unreadCount} הודעות שלא נקראו בעמוד זה
                </span>
              )}
            </p>
          </div>

          <button
            type="button"
            onClick={() => void refetch()}
            className="rounded-lg border px-4 py-2 hover:bg-gray-100"
          >
            רענן
          </button>
        </div>

        {/* Empty inbox */}
        {sortedThreads.length === 0 ? (
          <div className="rounded-xl border p-10 text-center">
            <h2 className="text-lg font-semibold">
              {total === 0 ? "אין הודעות פרטיות" : "אין שיחות בעמוד זה"}
            </h2>

            <p className="mt-2 text-gray-500">
              {total === 0
                ? "השיחות הפרטיות שלך יופיעו כאן."
                : "נסה לעבור לעמוד אחר."}
            </p>
          </div>
        ) : (
          <div className="overflow-hidden rounded-xl border">
            {sortedThreads.map((thread) => {
              const unread = thread.unread_count > 0;

              const title = thread.title?.trim() || `שיחה #${thread.id}`;

              return (
                <Link
                  key={thread.id}
                  to={`/private/${thread.id}`}
                  className={`
                  flex items-center gap-4
                  border-b p-4
                  transition-colors
                  last:border-b-0
                  hover:bg-gray-50
                  ${unread ? "bg-blue-50" : "bg-white"}
                `}
                >
                  {/* Avatar */}
                  <div
                    className="
                    flex h-12 w-12 shrink-0
                    items-center justify-center
                    rounded-full bg-gray-200
                    text-lg font-semibold
                    text-gray-600
                  "
                  >
                    {title.charAt(0)}
                  </div>

                  {/* Conversation details */}
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <h2
                        className={`
                        truncate text-base
                        ${unread ? "font-bold" : "font-medium"}
                      `}
                      >
                        {title}
                      </h2>

                      {/* Unread badge */}
                      {unread && (
                        <span
                          className="
                          rounded-full bg-blue-600
                          px-2 py-0.5
                          text-xs font-semibold text-white
                        "
                        >
                          {thread.unread_count}
                        </span>
                      )}
                    </div>

                    {/* Latest message */}
                    <p
                      className={`
                      mt-1 truncate text-sm
                      ${unread ? "font-medium text-gray-800" : "text-gray-500"}
                    `}
                    >
                      {stripHTML(thread?.last_message_content ?? "") ??
                        "אין הודעות להצגה"}
                    </p>

                    {/* Participants */}
                    <p className="mt-1 text-xs text-gray-400">
                      {thread.participants_count} משתתפים
                    </p>
                  </div>

                  {/* Date */}
                  <div className="shrink-0 text-xs text-gray-500">
                    {formatDateFull(
                      thread.last_message_at ?? thread.created_at,
                    )}
                  </div>
                </Link>
              );
            })}
          </div>
        )}

        {/* Pagination */}
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
