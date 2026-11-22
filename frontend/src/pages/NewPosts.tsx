import { useQuery } from "@tanstack/react-query";
import { getLatestPosts } from "../fetchMethods/getLatestPosts";
import type { LatestPost } from "../types";
import { useNavigate } from "react-router-dom";
import { useEffect, useState } from "react";
import { GetAvatar } from "../utils/GetAvatar";
// import { formatDateFull } from "../utils/formatDateFull";
import { formatDate } from "../utils/formatDate";
import HtmlContent from "../components/HtmlContent";

import { truncateHtml } from "../utils/truncateHtml";
export default function NewPosts() {
  const baseUrl = import.meta.env.BASE_URL;
  const navigate = useNavigate();
  const [page, setPage] = useState<number>(1);
  const [latestPosts, setLatestPosts] = useState<LatestPost[]>([]);
  const { data, isLoading, isFetching, isError, error } = useQuery({
    queryKey: ["newPosts", page],
    queryFn: () => getLatestPosts(page),
  });

  useEffect(() => {
    function init() {
      if (!data) return;
      setLatestPosts((prev) => [...prev, ...data]);
    }
    init();
  }, [data]);
  if (isLoading && latestPosts.length === 0) {
    return (
      <div className="mt-12 text-center text-2xl text-amber-300">טוען...</div>
    );
  }
  if (data) console.log(data);
  if (isError) {
    return (
      <div className="text-red-500  mt-12 text-2xl text-center">
        {error?.message}
      </div>
    );
  }
  return (
    <section className="mx-auto max-w-[1280px]">
      <div className="flex my-8 text-white justify-between items-center w-full">
        <h3 className="text-2xl font-semibold">הודעות אחרונות </h3>
      </div>
      <ul className="space-y-3 max-w-full">
        {latestPosts.map((item) => (
          <li
            key={item.id}
            className="max-w-full  rounded-md bg-[#555] sm:px-7 p-1 py-5 text-white flex gap-4"
          >
            <div className="flex">
              <GetAvatar
                name={item.open_user_name}
                image={item.open_user_image}
                size={30}
              />
            </div>
            <div className="flex min-w-0 flex-1 flex-col gap-2">
              <div className="flex w-full justify-between">
                <div
                  title="Go to Thread"
                  onClick={() =>
                    navigate(`/forum/${item.forum_id}/${item.thread_id}`)
                  }
                  className="cursor-pointer truncate break-all whitespace-pre-wrap text-lg  text-[#0BD7FD]"
                >
                  {item.thread_title}
                </div>{" "}
                <div className="text-center text-sm text-amber-950 flex justify-center items-center bg-amber-50 p-2 min-w-9 h-fit w-fit rounded-full ">
                  {item.messages_count}
                </div>
              </div>
              <div
                title={`${item.post_type === "reply" ? "Go to reply" : "Go to thread"}`}
                onClick={() => {
                  if (item.post_type === "reply") {
                    navigate(
                      `/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}#${item.id}`,
                    );
                  } else {
                    navigate(
                      `/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}`,
                    );
                  }
                }}
                className="mt-2  cursor-pointer w-full text-lg text-white"
              >
                <HtmlContent
                  html={truncateHtml(item.last_reply_content, 150)}
                />
              </div>
              <div className="flex sm:flex-row flex-col  gap-2 items-center">
                <div className="flex gap-2">
                  <img src={`${baseUrl}time.png`} alt="" />
                  <div className="text-white">
                    {formatDate(item.created_at)}
                  </div>
                </div>
                <div className="flex gap-2">
                  <div className="text-white">
                    {item.post_type === "reply"
                      ? item.last_reply_user_name
                      : item.open_user_name}
                  </div>

                  <span>
                    פרסם
                    {item.post_type === "reply" ? " תגובה " : " נושא "}
                  </span>
                </div>

                <span>בפורום {item.forum_name}</span>
              </div>
            </div>
          </li>
        ))}
      </ul>

      <div className="mt-4 flex w-full justify-center">
        <button
          disabled={isFetching}
          className="
      flex cursor-pointer items-center justify-center
      rounded bg-gray-900 px-4 py-2
      text-center text-2xl text-amber-100
      disabled:cursor-not-allowed
      disabled:opacity-50
    "
          onClick={() => setPage((prev) => prev + 1)}
        >
          {isFetching ? "טוען..." : "טען עוד"}
        </button>
      </div>
    </section>
  );
}
