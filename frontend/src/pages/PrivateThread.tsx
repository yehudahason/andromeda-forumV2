import {
  useLocation,
  Link,
  useParams,
  useSearchParams,
} from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  deletePrivateMessage,
  getPrivateThread,
} from "../fetchMethods/privateMessages";
import HtmlContent from "../components/HtmlContent";
// import { useEffect } from "react";
import Pagination from "../components/Paginatiom";
import { GetAvatar } from "../utils/GetAvatar";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { formatDateFull } from "../utils/formatDateFull";
import { markPrivateThreadRead } from "../fetchMethods/privateMessages";
import { useUserStore } from "../stores/userStore";
import type { EditPrivateMessageProps } from "./EditPrivateMessage";
import EditPrivateMessage from "./EditPrivateMessage";

export default function PrivateThread() {
  const location = useLocation();
  const navigate = useNavigate();
  const user = useUserStore((state) => state.user);
  const { tid } = useParams<{ tid: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const baseUrl = import.meta.env.BASE_URL;
  const threadID = Number(tid);
  const queryClient = useQueryClient();
  const rawPage = Number(searchParams.get("page") ?? 1);
  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;

  const validThreadID = Number.isSafeInteger(threadID) && threadID > 0;

  const [showEdit, setShowEdit] = useState<EditPrivateMessageProps | null>(
    null,
  );
  const { data, isLoading, isError, error, isFetching, refetch } = useQuery({
    queryKey: ["privateMessages", threadID, page],
    queryFn: ({ signal }) => getPrivateThread(threadID, page, signal),
    enabled: validThreadID,
  });
  async function deleteMsg(id: number) {
    try {
      const result = await deletePrivateMessage(id);

      if (result.thread_deleted) {
        await queryClient.invalidateQueries({
          queryKey: ["privateThreads"],
        });

        navigate("/inbox", { replace: true });
        return;
      }

      const response = await refetch();

      if (!response.isSuccess || !response.data) return;

      const newTotalPages = Math.max(
        1,
        Math.ceil(response.data.total / response.data.per_page),
      );

      if (page > newTotalPages) {
        setSearchParams((prev) => {
          const next = new URLSearchParams(prev);
          next.set("page", String(newTotalPages));
          return next;
        });
      }
    } catch (error) {
      console.error("Failed to delete message:", error);
    }
  }
  //Scroll to id
  useEffect(() => {
    if (!data?.messages.length || !location.hash) return;

    const id = decodeURIComponent(location.hash.slice(1));

    const element = document.getElementById(id);

    if (element) {
      element.scrollIntoView({
        // behavior: "smooth",
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

  if (showEdit) {
    return <EditPrivateMessage {...showEdit} setShowEdit={setShowEdit} />;
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
        <a className="text-white" href="/inbox">
          Inbox
        </a>
        {data?.messages.length === 0 ? (
          <p className="text-center text-gray-500">אין הודעות להצגה</p>
        ) : (
          <>
            {data?.messages.map((message, index) => (
              <div
                id={String(message.id)}
                key={message.id}
                className="flex relative  bg-neutral-600 gap-4 rounded-lg border border-gray-700 py-2 px-2"
              >
                {message.sender_id === user?.id && (
                  <>
                    {/* Delete Botton */}
                    <button
                      type="button"
                      title={`${index === 0 ? "Delete Thread" : "Delete Message"}`}
                      aria-label="Delete Message"
                      onClick={() => {
                        if (index === 0) {
                          const ok = confirm("Delete  private thread?");
                          if (ok) deleteMsg(message.id);
                        } else {
                          deleteMsg(message.id);
                        }
                      }}
                      className="border-0 z-2 absolute left-2 top-2 bg-transparent"
                    >
                      <img
                        className=" w-4 h-4"
                        src={`${baseUrl}delete.png`}
                        alt=""
                      />
                    </button>
                    {/* Edit link */}
                    <button
                      onClick={() =>
                        setShowEdit({
                          t: threadID,
                          id: message.id,
                          content: message.content,
                          page: page,
                        })
                      }
                      title="Edit Message"
                      className="cursor-pointer  border-0 z-2 absolute left-3 bottom-3 bg-transparent"
                    >
                      <img
                        className=" w-4 h-4"
                        src={`${baseUrl}edit.png`}
                        alt=""
                      />
                    </button>
                  </>
                )}
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
