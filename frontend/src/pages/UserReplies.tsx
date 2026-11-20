import { useSearchParams, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getUserReplies } from "../fetchMethods/getUseReplies";
import { useEffect, useMemo } from "react";
import Pagination from "../components/Paginatiom";
// import { GetAvatar } from "../utils/GetAvatar";
import { formatDate } from "../utils/formatDate";

export default function UserReplies() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { userId } = useParams<{ userId: string }>();
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
    console.log("user replies:", data);
  }, [data]);
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
      <section
        dir="rtl"
        className=" min-h-[80vh] flex flex-col  mx-auto max-w-7xl px-4 py-6"
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
          <h1 className="text-2xl py-4 text-white font-bold">כל ההודעות</h1>
        </div>
        <div className="flex w-full  flex-1 bg-neutral-600 p-6 rounded-xl">
          <ul className="flex flex-col gap-3">
            {replies.map((item) => {
              return (
                <li key={item.id} className="text-white text-lg">
                  <a
                    href={`/forum/${item.forum_id}/${item.thread_id}/?tpage=${item.thread_page}#${item.id}`}
                  >
                    <span className="flex items-center gap-4">
                      <span>{formatDate(item.created_at)}</span>
                      <span className="truncate">
                        {formatDate(item.created_at)} {item.forum_name} הגיב
                        בדיון- {item.post}
                      </span>
                    </span>
                  </a>
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
