import { useState, useRef, useEffect } from "react";
import Pagination from "./Paginatiom";
import { formatDateFull } from "../utils/formatDateFull";
import { Link, useNavigate } from "react-router-dom";
import { GetAvatar } from "../utils/GetAvatar";
import type { ReplyType } from "../types";
import type { ThreadDetails } from "../types";
import { deleteReply } from "../fetchMethods/deleteReply";
import { useQueryClient } from "@tanstack/react-query";

type RepliesProp = {
  replies: ReplyType[];
  current: string;
  forum: string;
  tid: string;
  total: number;
  tdetails: ThreadDetails | null;
};

export default function Replies({
  tid,
  forum,
  total,
  replies,
  current,
  tdetails,
}: RepliesProp) {
  const navigate = useNavigate();
  const [currentPage, setCurrenpage] = useState(+current);
  const baseUrl = import.meta.env.BASE_URL;
  const queryClient = useQueryClient();

  function handlePage(page: number) {
    setCurrenpage(page);
    navigate(`/forum/${forum}/${tid}/?tpage=${page}`);
    scrollToTop();
  }

  const [isDeleting, setIsDeleting] = useState<boolean>(false);
  const deleteController = useRef<AbortController | null>(null);

  async function handleDeleteReply(id: string) {
    if (!id) return;

    // Abort previous delete request if still running
    deleteController.current?.abort();

    const controller = new AbortController();
    deleteController.current = controller;
    setIsDeleting(true);

    try {
      await deleteReply(id, controller.signal);

      await queryClient.invalidateQueries({
        queryKey: ["replies"],
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
    <ul className="w-full flex flex-col gap-8">
      {/* Header */}
      {replies && tdetails && (
        <>
          <li className="flex h-fit items-center justify-between  border-b border-white/15 ">
            <Pagination
              total={total}
              currentPage={currentPage}
              onPageChange={handlePage}
            />
          </li>
          {currentPage === 1 && (
            <li
              key={tdetails.id}
              dir="rtl"
              className=" rounded-md bg-[#555] sm:px-7 p-1 py-5 text-white"
            >
              {/* Header */}

              <div className="w-full flex flex-col gap-4">
                <div className="break-all pb-4 border-b border-b-neutral-500 text-center text-2xl">
                  {tdetails.title}
                </div>

                <div className="flex  sm:pr-4  pr-2 sm:gap-8 gap-2">
                  <div className="flex mt-6 flex-col gap-4 justify-start items-center">
                    <span className="sm:w-30 w-20 text-center font-medium flex gap-2">
                      <p>{tdetails.author.name}</p>
                    </span>
                    <span className="">
                      {GetAvatar({
                        name: tdetails.author.name,
                        image: tdetails.author.image,
                        size: 56,
                      })}
                    </span>

                    <span className="flex items-center gap-1 text-sm">
                      <span>{tdetails.author.replies_count}</span>
                      <span>{formatDateFull(tdetails.author.created_at)}</span>
                      <span>💬</span>
                    </span>
                  </div>
                  <div
                    className="
                    [&_a]:text-sky-400
                    [&_a]:underline
           [&_ul]:list-disc
[&_ul]:ps-6
[&_ul]:list-outside

[&_ol]:list-decimal
[&_ol]:ps-6
[&_ol]:list-outside

[&_li]:my-1
    w-full
    max-w-full
    min-w-0
    overflow-hidden

    [&>div]:w-full
    [&>div]:max-w-full
    [&>div]:min-w-0

    [&_pre]:w-full
    [&_pre]:max-w-full
    [&_pre]:min-w-0
    [&_pre]:overflow-x-auto
    [&_pre]:whitespace-pre

    [&_code]:block
    [&_code]:max-w-full
    [&_code]:min-w-0
    [&_code]:[direction:ltr]
  "
                    dangerouslySetInnerHTML={{
                      __html: tdetails.content,
                    }}
                  />
                </div>
                <div className="flex sm:flex-row flex-col gap-4 items-center justify-between">
                  <div className=" sm:mr-40 mr-20 flex  gap-4  flex-wrap">
                    <span className="flex flex-wrap gap-2">
                      <p>{formatDateFull(tdetails.created_at)}</p>
                    </span>
                  </div>

                  <div className="flex gap-4 justify-center items-center">
                    <Link to={`/editThread/${forum}/${tdetails.id}`}>
                      <img src={`${baseUrl}edit.png`} alt="" />
                    </Link>
                    <button className="py-2 px-4 bg-none rounded-lg">
                      שתף
                    </button>
                    <button className="py-2 px-4 bg-gray-300 text-black rounded-lg">
                      עקוב
                    </button>
                  </div>
                </div>
              </div>
            </li>
          )}
        </>
      )}

      {replies.map((reply) => (
        <li
          key={reply.id}
          id={reply.id}
          dir="rtl"
          className="relative rounded-md bg-[#555] sm:px-5 p-1 py-4 text-white"
        >
          {/* Header */}
          <button
            disabled={isDeleting}
            title="מחק תגובה"
            onClick={() => handleDeleteReply(reply.id)}
            className="absolute top-1 left-3 cursor-pointer"
          >
            <img className="w-3 h-3.5" src={`${baseUrl}delete.png`} alt="" />
          </button>

          <div className="w-full flex sm:gap-8 gap-4 min-w-0">
            <div className="flex sm:w-30 w-20 shrink-0 flex-col justify-start pt-6 gap-6 items-center">
              <span className="text-center">{reply.author.name}</span>

              {GetAvatar({
                name: reply.author.name,
                image: reply.author.image,
                size: 50,
              })}

              <span className="flex items-center gap-1 text-sm">
                {reply.author.replies_count}
                <span>💬</span>
                <span>{formatDateFull(reply.author.created_at)}</span>
              </span>
            </div>

            <div className="flex flex-col flex-1 min-w-0">
              <p className="w-full text-right text-sm text-gray-200">
                {formatDateFull(reply.created_at)}
              </p>

              <div className="border-b border-b-gray-500 min-w-0">
                <h2 className="mb-2 text-lg font-medium">Re:{reply.title}</h2>

                <div
                  className="
                   [&_a]:text-sky-400
                    [&_a]:underline
                  [&_ul]:list-disc
[&_ul]:ps-6
[&_ul]:list-outside

[&_ol]:list-decimal
[&_ol]:ps-6
[&_ol]:list-outside

[&_li]:my-1
          w-full
          max-w-full
          min-w-0
          overflow-hidden
          text-base
          mb-6
          leading-8
          wrap-anywhere
          text-gray-100

          [&>div]:max-w-full
          [&>div]:min-w-0

          [&_p]:max-w-full
          [&_p]:break-words

          [&_pre]:block
          [&_pre]:w-full
          [&_pre]:max-w-full
          [&_pre]:min-w-0
          [&_pre]:overflow-x-auto
          [&_pre]:whitespace-pre

          [&_code]:block
          [&_code]:max-w-full
          [&_code]:min-w-0
          [&_code]:font-mono
          [&_code]:[direction:ltr]
        "
                  dangerouslySetInnerHTML={{
                    __html: reply.post,
                  }}
                />
              </div>

              {/* Footer */}
              <div className="mt-4 w-full flex items-center justify-between">
                <div className="flex items-center gap-8">
                  {/* Quote */}
                  <button
                    type="button"
                    className="flex items-center gap-2 text-sm"
                  >
                    <span>ציטוט</span>
                    <span className="flex h-9 w-9 items-center justify-center rounded bg-white text-black">
                      ✓
                    </span>
                  </button>
                  <Link to={`/editReply/${forum}/${tid}/${reply.id}`}>
                    <img src={`${baseUrl}edit.png`} alt="" />
                  </Link>
                </div>
                {/* Like */}
                <button
                  type="button"
                  className="flex h-10 w-10 items-center justify-center rounded-full bg-gray-300 text-2xl text-white"
                >
                  ♥
                </button>
              </div>
            </div>
          </div>
        </li>
      ))}
      <li className="flex h-fit items-center justify-between border-b border-white/15 ">
        <Pagination
          total={total}
          currentPage={currentPage}
          onPageChange={handlePage}
        />
      </li>
    </ul>
  );
}
