import {
  useLocation,
  Link,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getPrivateMessages } from "../fetchMethods/privateMessages/";
import HtmlContent from "../components/HtmlContent";
// import { useEffect } from "react";
import Pagination from "../components/Paginatiom";
import { GetAvatar } from "../utils/GetAvatar";
import { useEffect } from "react";
import { formatDateFull } from "../utils/formatDateFull";
import { markPrivateThreadRead } from "../fetchMethods/privateMessages/";
export default function PrivateMessagesPage() {
  const location = useLocation();
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

  useEffect(() => {
    if (!data?.messages.length || !location.hash) return;

    const id = decodeURIComponent(location.hash.slice(1));

    const element = document.getElementById(id);

    if (element) {
      element.scrollIntoView({
        behavior: "smooth",
        block: "center",
      });
    }
  }, [data, location.hash]);
  useEffect(() => {
    if (!data || !threadID) return;
    console.log(data);

    markPrivateThreadRead(threadID);
  }, [threadID, data]);
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

      {isFetching && <p className="text-sm text-gray-400">מעדכן הודעות...</p>}

      {/* Messages */}
      <div className="flex flex-col gap-4 text-white">
        {data?.messages.length === 0 ? (
          <p className="text-center text-gray-500">אין הודעות להצגה</p>
        ) : (
          <>
            {data?.messages.map((message, index) => (
              <div
                id={String(message.id)}
                key={message.id}
                className="flex  bg-neutral-600 gap-4 rounded-lg border border-gray-700 py-2 px-2"
              >
                <div className="mb-2 flex flex-col items-center justify-center gap-3 py-4 pr-1">
                  <h4 className="whitespace-nowrap">{message.sender_name}</h4>
                  {GetAvatar({
                    name: message.sender_name,
                    image: message.sender_image,
                    size: 40,
                  })}
                </div>
                <div className="relative flex w-full flex-col gap-4 justify-end">
                  {index === 0 && (
                    <h2 className="absolute top-0 w-full pr-4 text-xl font-bold whitespace-nowrap">
                      {data?.messages[0]?.thread_title}
                    </h2>
                  )}

                  <HtmlContent html={message.content} />
                  <p className="text-center text-gray-200">
                    {formatDateFull(message.created_at)}
                  </p>
                </div>
              </div>
            ))}
          </>
        )}
      </div>

      <Link
        className="bg-sky-600 w-fit px-2 py-1 rounded text-neutral-300"
        to={`/privatemessage/${tid}`}
      >
        {" "}
        שלח תגובה
      </Link>

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
