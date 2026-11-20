import { useSearchParams, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getUserThreads } from "../fetchMethods/getUserThreads";
import { useEffect, useMemo } from "react";
import Pagination from "../components/Paginatiom";
// import { GetAvatar } from "../utils/GetAvatar";
import { formatDate } from "../utils/formatDate";

export default function UserThreads() {
  const [searchParams, setSearchParams] = useSearchParams();
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
          <h1 className="text-2xl py-4 text-white font-bold">כל השירשורים</h1>
          <a className="text-white m-2" href={`/users/${userId}/threads`}>
            כל השירשורים
          </a>
          <a className="text-white" href={`/users/${userId}/replies`}>
            כל ההודעות
          </a>
        </div>
        <div className="flex w-full  flex-1 bg-neutral-600 p-6 rounded-xl">
          <ul className="flex flex-col gap-3">
            {threads.map((item) => {
              return (
                <li key={item.id} className="text-white text-lg">
                  <a href={`/forum/${item.forum_id}/${item.id}`}>
                    <span className="flex items-center gap-4">
                      <span>{formatDate(item.created_at)}</span>
                      <span className="truncate">
                        {formatDate(item.created_at)} {item.forum_name} הגיב
                        בדיון- {item.title}
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
