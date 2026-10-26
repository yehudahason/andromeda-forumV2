import { useParams, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getPrivateMessages } from "../fetchMethods/privateMessages/";
import HtmlContent from "../components/HtmlContent";
// import { useEffect } from "react";
import Pagination from "../components/Paginatiom";

export default function PrivateMessagesPage() {
  const { tid } = useParams<{ tid: string }>();
  const [searchParams, setSearchParams] = useSearchParams();

  const threadID = Number(tid);

  const rawPage = Number(searchParams.get("page") ?? 1);
  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;

  const validThreadID = Number.isSafeInteger(threadID) && threadID > 0;

  const { data, isLoading, isError, error, isFetching } = useQuery({
    queryKey: ["privateMessages", threadID, page],
    queryFn: ({ signal }) => getPrivateMessages(threadID, page, signal),
    enabled: validThreadID,
  });

  const total = data?.total ?? 1;
  // Calculate total pages
  const totalPages = data ? Math.ceil(data.total / data.per_page) : 0;

  function changePage(newPage: number) {
    if (newPage < 1 || (totalPages > 0 && newPage > totalPages)) {
      return;
    }

    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      next.set("page", String(newPage));
      return next;
    });
  }

  if (!validThreadID) {
    return <div>מזהה שיחה לא תקין</div>;
  }

  if (isLoading) {
    return <div>טוען הודעות...</div>;
  }

  if (isError) {
    return (
      <div className="text-red-500">
        {error instanceof Error ? error.message : "שגיאה בטעינת ההודעות"}
      </div>
    );
  }

  return (
    <div
      dir="rtl"
      className="mx-auto  text-white flex w-full max-w-4xl flex-col gap-4 p-4"
    >
      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex h-fit  items-center justify-between border-b mb-4 border-white/15 ">
          <Pagination
            total={total}
            currentPage={page}
            onPageChange={changePage}
          />
        </div>
      )}
      <h1 className="text-2xl font-bold">הודעות פרטיות</h1>

      {isFetching && <p className="text-sm text-gray-400">מעדכן הודעות...</p>}

      {/* Messages */}
      <div className="flex flex-col gap-4 text-white">
        {data?.messages.length === 0 ? (
          <p className="text-center text-gray-500">אין הודעות להצגה</p>
        ) : (
          data?.messages.map((message) => (
            <div
              key={message.id}
              className="rounded-lg border border-gray-700 p-4"
            >
              <div className="mb-2 flex justify-between gap-3">
                <span className="text-sm text-sky-400">
                  {message.sender_id ?? "משתמש לא ידוע"}
                </span>

                <time className="text-xs text-gray-400">
                  {new Date(message.created_at).toLocaleString("he-IL", {
                    timeZone: "Asia/Jerusalem",
                    dateStyle: "short",
                    timeStyle: "short",
                  })}
                </time>
              </div>

              <HtmlContent html={message.content} />
            </div>
          ))
        )}
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex h-fit  items-center justify-between border-b mb-4 border-white/15 ">
          <Pagination
            total={total}
            currentPage={page}
            onPageChange={changePage}
          />
        </div>
      )}
    </div>
  );
}
