import { useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getNotifications } from "../fetchMethods/privateMessages/notificationFuncs";
import { useEffect, useMemo } from "react";
import Pagination from "../components/Paginatiom";
// import { GetAvatar } from "../utils/GetAvatar";

export default function AllNotification() {
  const [searchParams, setSearchParams] = useSearchParams();

  // Read page from URL.
  const rawPage = Number(searchParams.get("page") ?? "1");

  const page = Number.isSafeInteger(rawPage) && rawPage > 0 ? rawPage : 1;
  // const queryClient = useQueryClient();
  const { data, isPending, isError, error } = useQuery({
    queryKey: ["notifications", page],
    queryFn: ({ signal }) => getNotifications(page, signal),
    refetchInterval: 10 * 60 * 1000,
  });
  //To refetch notifications after update
  // const refreshNotifications = async () => {
  //   await queryClient.invalidateQueries({
  //     queryKey: ["notifications"],
  //   });
  // };

  const notifications = useMemo(() => {
    return data?.notifications ?? [];
  }, [data]);

  const total = data?.total ?? 0;

  const totalPages = data?.total_pages ?? 1;

  function changePage(newPage: number) {
    if (newPage < 1 || newPage > totalPages) return;

    setSearchParams({ page: String(newPage) });
  }
  useEffect(() => {
    console.log("test:", notifications);
  }, [notifications]);
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
      <main dir="rtl" className="mx-auto max-w-4xl px-4 py-6">
        {totalPages && (
          <div className="flex h-fit items-center justify-between border-b  border-white/15 ">
            <Pagination
              total={total}
              currentPage={page}
              onPageChange={changePage}
            />
          </div>
        )}
        {/* Header */}

        <div>
          <h1 className="text-2xl py-4 text-white font-bold">כל ההתראות</h1>
        </div>
        <ul>
          {notifications.map((item) => {
            return <li className="text-white">{item.actor_name}</li>;
          })}
        </ul>
        {totalPages > 1 && (
          <div className="flex h-fit items-center justify-between border-b  border-white/15 ">
            <Pagination
              total={total}
              currentPage={page}
              onPageChange={changePage}
            />
          </div>
        )}
      </main>
    </>
  );
}
