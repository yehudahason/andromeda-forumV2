import { useParams, Link } from "react-router-dom";
import { useSearchParams } from "react-router-dom";
import ThreadList from "../components/ThreadList";
import { getThreads } from "../fetchMethods/getThreads";
import type { ThreadType } from "../types";
import { useQuery } from "@tanstack/react-query";
export default function ForumPage() {
  const { f } = useParams();
  const [searchParams] = useSearchParams();
  const page = searchParams.get("page");

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["threads", f, page],
    queryFn: () => getThreads(f, Number(page ?? "1")),
  });

  const threads: ThreadType[] = data?.threads ?? [];
  const total = data?.total ?? 0;
  const forumName = data?.forum_name ?? "";
  if (isLoading) {
    return (
      <div className="text-amber-300  mt-12 text-2xl text-center">טוען...</div>
    );
  }

  if (isError) {
    return (
      <div className="text-red-500  mt-12 text-2xl text-center">
        {error.message}
      </div>
    );
  }

  return (
    <section className="mx-auto max-w-[1280px]">
      <div className="flex my-8 text-white justify-between items-center w-full">
        <h3 className="text-2xl font-semibold">{forumName}</h3>
        <Link
          className="bg-sky-400 text-black py-2 px-4 rounded-lg"
          to={`/post/${f}`}
        >
          פתח נושא חדש
        </Link>
      </div>
      <ThreadList
        total={total}
        forum={f ?? "1"}
        threads={threads}
        current={page ?? "1"}
      />
    </section>
  );
}
