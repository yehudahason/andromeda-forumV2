import { useState } from "react";
import Pagination from "./Paginatiom";
import { formatDate } from "../utils/formatDate";
import { useNavigate } from "react-router-dom";
import { deleteThread } from "../fetchMethods/deleteThread";
import { useQueryClient } from "@tanstack/react-query";
import type { ThreadType } from "../types";
import { useRef, useEffect } from "react";
type ThreadListProps = {
  threads: ThreadType[];
  current: string;
  forum: string;
  total: number;
};

export default function ThreadList({
  forum,
  threads,
  current,
  total,
}: ThreadListProps) {
  const baseUrl = import.meta.env.BASE_URL;
  const navigate = useNavigate();
  const [currentPage, setCurrenpage] = useState(+current);
  const queryClient = useQueryClient();
  const [isDeleting, setIsDeleting] = useState(false);

  function handlePage(page: number) {
    setCurrenpage(page);
    navigate(`/forum/${forum}/?page=${page}`);
    scrollToTop();
  }

  const deleteController = useRef<AbortController | null>(null);

  async function handleDeleteThread(id: number) {
    if (!id) return;

    // Abort previous delete request if still running
    deleteController.current?.abort();

    const controller = new AbortController();
    deleteController.current = controller;
    setIsDeleting(true);

    try {
      await deleteThread(id, controller.signal);

      await queryClient.invalidateQueries({
        queryKey: ["threads"],
      });
    } catch (e) {
      if (e instanceof Error && e.name === "AbortError") {
        console.log("Delete request aborted");
        return;
      }

      console.log(e);
    } finally {
      if (deleteController.current === controller) {
        deleteController.current = null;
        setIsDeleting(false);
      }
    }
  }

  const scrollToTop = () => {
    window.scrollTo(0, 0);
  };
  useEffect(() => {
    return () => {
      deleteController.current?.abort();
    };
  }, []);
  return (
    <>
      <div className="flex h-fit items-center justify-between border-b mb-4 border-white/15 ">
        <Pagination
          total={total}
          currentPage={currentPage}
          onPageChange={handlePage}
        />
      </div>
      <ul className="w-full overflow-hidden rounded-md bg-[#555] text-white">
        {/* Header */}
        <li className="flex h-fit items-center justify-between border-b border-white/15 "></li>

        {threads.map((thread) => (
          <li
            key={thread.id}
            dir="rtl"
            className="relative grid min-h-[120px] p-4 gap-4 grid-cols-1 sm:grid-cols-[1fr_100px_1fr] items-center border-b 
           border-white/15  last:border-b-0"
          >
            <button
              disabled={isDeleting}
              title="מחק אשכול"
              onClick={() => {
                const confirmed = confirm(
                  "Are you sure to delete this Thread?",
                );
                if (confirmed) handleDeleteThread(thread.id);
              }}
              className="absolute top-1 left-3 cursor-pointer"
            >
              <img className="w-3 h-3.5" src={`${baseUrl}delete.png`} alt="" />
            </button>
            {/* Forum */}
            <div className="flex justify-start min-w-0 items-center gap-5 text-right">
              {/* Text */}
              <div className="min-w-0">
                <a
                  href={`/forum/${thread.forum_id}/${thread.id}`}
                  className="block flex-1  truncate text-[20px] font-medium text-[#0BD7FD] hover:underline"
                >
                  {thread.title}
                </a>

                <p className="truncate text-[16px] text-white">
                  <span>נפתח על ידי -</span>
                  <span>
                    {thread.author} {formatDate(thread.created_at)}
                  </span>
                </p>
              </div>
            </div>

            {/* Messages */}
            <div className="sm:text-center text-right px-2">
              <p className="text-2xl">
                {thread.messages_count.toLocaleString()}
              </p>

              <p className="text-sm text-white/90">הודעות</p>
            </div>

            {/* Last post */}
            <div className="min-w-0 text-right px-2">
              {thread.last_post_title && (
                <a
                  href={`/forum/${thread.forum_id}/${thread.id}`}
                  className="block truncate text-[18px] text-[#0BD7FD] hover:underline"
                >
                  {thread.last_post_title}
                </a>
              )}
              <div className="flex items-center gap-1">
                {thread.last_post_author && (
                  <p className="mt-1 text-sm text-white">
                    על-ידי {thread.last_post_author}
                  </p>
                )}
                ,
                {thread.last_post_date && (
                  <p className="text-sm mt-1 text-white">
                    {formatDate(thread.last_post_date)}
                  </p>
                )}
              </div>
            </div>
          </li>
        ))}
      </ul>
      <div className="flex h-fit items-center justify-between border-b border-white/15 ">
        <Pagination
          total={total}
          currentPage={currentPage}
          onPageChange={handlePage}
        />
      </div>
    </>
  );
}
