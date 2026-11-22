import { useSearchParams, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getUserReplies } from "../fetchMethods/getUseReplies";
import { useEffect, useMemo, useState } from "react";
import Pagination from "../components/Paginatiom";
// import { GetAvatar } from "../utils/GetAvatar";
import { type User } from "../types";
import { getUserByID } from "../fetchMethods/getUserByID";
import { formatDate } from "../utils/formatDate";
import { truncateHtml } from "../utils/truncateHtml";
import HtmlContent from "../components/HtmlContent";
export default function UserReplies() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { userId } = useParams<{ userId: string }>();
  const [user, setUser] = useState<User | undefined>(undefined);
  // Read page from URL.
  const rawPage = Number(searchParams.get("page") ?? "1");

  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;
  // const queryClient = useQueryClient();
  const { data, isPending, isError, error } = useQuery({
    queryKey: ["profileThreads", userId, page],
    queryFn: ({ signal }) => getUserReplies(userId ?? "", page, signal),
    enabled: !!userId,
  });

  const replies = useMemo(() => {
    return data?.replies ?? [];
  }, [data]);

  const total = data?.total ?? 0;

  const totalPages = data?.total_pages ?? 1;

  function changePage(newPage: number) {
    if (newPage < 1 || newPage > totalPages) return;

    setSearchParams({ page: String(newPage) });
  }

  useEffect(() => {
    async function init() {
      if (userId) {
        const userRes = await getUserByID(userId);
        setUser(userRes);
        console.log("user page:", userRes);
      }
    }

    init();
  }, [userId]);
  useEffect(() => {
    console.log("user replies:", data);
  }, [data]);
  if (isPending) {
    return (
      <div dir="rtl" className="mx-auto max-w-4xl p-6">
        <p className="text-white">טוען...</p>
      </div>
    );
  }

  if (isError) {
    return (
      <div dir="rtl" className="mx-auto max-w-4xl p-6">
        <p className="text-red-500 mb-6">שגיאה: {error.message}</p>

        <a
          href={`/users/${userId}/replies`}
          className="m-4 rounded bg-blue-600 px-4 py-2 text-white"
        >
          נסה שוב
        </a>
        <a href={`/`} className="m-4 rounded bg-blue-600 px-4 py-2 text-white">
          חזור לדף הבית
        </a>
      </div>
    );
  }

  return (
    <>
      <section
        dir="rtl"
        className="gap-4 min-h-[80vh] flex flex-col  mx-auto max-w-7xl sm:px-4 px-1 py-3"
      >
        {totalPages && (
          <div className="flex w-full h-fit items-center justify-between border-b  border-white/15 ">
            <Pagination
              total={total}
              currentPage={page}
              onPageChange={changePage}
            />
          </div>
        )}
        {/* Header */}

        <div>
          <h1
            className="
          text-2xl py-4 text-white font-bold"
          >
            {user?.name}
          </h1>
          <a className="text-white m-2" href={`/users/${userId}/threads`}>
            כל השירשורים
          </a>
          <a className="text-sky-500 m-2" href={`/users/${userId}/replies`}>
            כל ההודעות
          </a>
        </div>
        <div className="flex w-full  flex-1 bg-neutral-600  p-1 sm:p-6 rounded-xl">
          <ul className="flex flex-col w-full gap-3">
            {replies.map((item, index) => {
              return (
                <li
                  key={item.id}
                  className="text-white w-full border-b
                   border-b-sky-900 text-lg sm:p-3 p-1"
                >
                  <span className="flex min-w-0 break-all w-full flex-col sm:flex-row   items-center sm:gap-8 gap-2">
                    <span>#{index + 1 + (page - 1) * 14} </span>
                    <span>{formatDate(item.created_at)}</span>
                    <a
                      title="Go to reply"
                      href={`/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}#${item.id}`}
                      className="w-full min-w-0"
                    >
                      <HtmlContent html={truncateHtml(item.post, 150)} />
                    </a>
                    <a
                      title="Go to forum"
                      href={`/forum/${item.forum_id}`}
                      className="whitespace-nowrap font-bold"
                    >
                      בפורום- {item.forum_name}
                    </a>
                  </span>
                </li>
              );
            })}
          </ul>
        </div>
        {totalPages > 1 && (
          <div className="flex h-fit items-center justify-between border-b  border-white/15 ">
            <Pagination
              total={total}
              currentPage={page}
              onPageChange={changePage}
            />
          </div>
        )}
      </section>
    </>
  );
}
