import { useSearchParams, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getUserThreads } from "../fetchMethods/getUserThreads";
import { useEffect, useMemo, useState } from "react";
import Pagination from "../components/Paginatiom";
// import { GetAvatar } from "../utils/GetAvatar";
import { formatDate } from "../utils/formatDate";
import { getUserByID } from "../fetchMethods/getUserByID";
import type { User } from "../types";
import ProfileHeader from "../components/ProfileHeader";
export default function UserThreads() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [user, setUser] = useState<User | undefined>(undefined);
  const { userId } = useParams<{ userId: string }>();
  // Read page from URL.
  const rawPage = Number(searchParams.get("page") ?? "1");

  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;
  // const queryClient = useQueryClient();
  const { data, isPending, isError, error } = useQuery({
    queryKey: ["profileThreads", userId, page],
    queryFn: ({ signal }) => getUserThreads(userId ?? "", page, signal),
    enabled: !!userId,
  });

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
  const threads = useMemo(() => {
    return data?.threads ?? [];
  }, [data]);

  const total = data?.total ?? 0;

  const totalPages = data?.total_pages ?? 1;

  function changePage(newPage: number) {
    if (newPage < 1 || newPage > totalPages) return;

    setSearchParams({ page: String(newPage) });
  }
  useEffect(() => {
    console.log("user threads:", data);
  }, [data]);
  if (isPending) {
    return (
      <div dir="rtl" className="mx-auto  max-w-4xl p-6">
        <p className="text-white">טוען פרופיל ...</p>
      </div>
    );
  }

  if (isError) {
    return (
      <div dir="rtl" className="mx-auto max-w-4xl p-6">
        <p className="text-red-500 mb-6">שגיאה: {error.message}</p>

        <a
          href={`/users/${userId}/threads`}
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
        className=" min-h-[80vh] flex flex-col gap-4 mx-auto max-w-7xl sm:px-4 px-0.5 py-3"
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

        <ProfileHeader user={user} userId={userId} isThreads={true} />
        <div className="flex w-full  flex-1 bg-neutral-600 p-2 sm:p-6 rounded-xl">
          <ul className="flex  w-full flex-col gap-3 ">
            {threads.map((item, index) => {
              return (
                <li
                  key={item.id}
                  className="text-white 
                border-b border-b-blue-800 pb-2 
                text-lg"
                >
                  <span className="flex break-all flex-col sm:flex-row  items-center sm:gap-4 gap-2">
                    <span className="py-0.5 px-2 rounded bg-sky-900 text-white">
                      {`${index + 1 + (page - 1) * 14}`}
                    </span>
                    <span className="whitespace-nowrap">
                      {formatDate(item.created_at)}
                    </span>
                    <a
                      title="Go to thread"
                      href={`/forum/${item.forum_id}/${item.id}`}
                      className="break-all"
                    >
                      {item.title}
                    </a>

                    <a
                      title="Go to forum"
                      href={`/forum/${item.forum_id}`}
                      className="font-bold whitespace-nowrap"
                    >
                      בפורום -{item.forum_name}
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
