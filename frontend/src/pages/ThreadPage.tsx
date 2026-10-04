import { useSearchParams, useParams, Link } from "react-router-dom";
import { useLocation } from "react-router-dom";
import { useEffect } from "react";
import Replies from "../components/Replies";
import { getReplies } from "../fetchMethods/fetchReplies";
import { getThreadByID } from "../fetchMethods/getThreadByID";
import type { ReplyType } from "../types";
import type { ThreadDetails } from "../types";
import { useQuery } from "@tanstack/react-query";

export default function ThreadPage() {
  const { f, t } = useParams();
  const [searchParams] = useSearchParams();
  const tpage = searchParams.get("tpage");
  const location = useLocation();

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["replies", f, t, tpage],
    queryFn: () => getReplies(t ?? 1, Number(tpage ?? "1")),
  });
  const {
    data: data2,
    isLoading: isLoading2,
    isError: isError2,
    error: error2,
  } = useQuery({
    queryKey: ["getThread", f, t],
    queryFn: () => getTID(),
  });

  async function getTID() {
    if (!t) return;
    if (!f) return;
    return getThreadByID(+t, +f);
  }

  useEffect(() => {
    if (!data || !location.hash) return;

    const id = decodeURIComponent(location.hash.slice(1));

    let attempts = 0;
    let timeout: ReturnType<typeof setTimeout>;

    const scroll = () => {
      const element = document.getElementById(id);

      if (element) {
        element.scrollIntoView({
          behavior: "instant",
          block: "center",
        });
        return;
      }

      if (attempts < 10) {
        attempts++;
        timeout = setTimeout(scroll, 50);
      }
    };

    scroll();

    return () => clearTimeout(timeout);
  }, [data, location.hash]);
  const replies: ReplyType[] | undefined = data?.replies;
  const total: number | undefined = data?.total;
  const tdetails: ThreadDetails | undefined = data2;

  if (isLoading || isLoading2) {
    return (
      <div className="text-amber-300  mt-12 text-2xl text-center">טוען...</div>
    );
  }

  if (isError) {
    return (
      <div className="text-red-500  mt-12 text-2xl text-center">
        {error?.message}
      </div>
    );
  }
  if (isError2) {
    return (
      <div className="text-red-500  mt-12 text-2xl text-center">
        {error2?.message}
      </div>
    );
  }
  return (
    <section className="mx-auto max-w-[1280px]">
      <div className="flex my-8 text-white justify-between items-center w-full">
        <h3 className="text-2xl font-semibold">{tdetails?.forum_name}</h3>
        <Link
          className="bg-sky-400 text-black py-2 px-4 rounded-lg"
          to={`/post/${f}/${t}`}
        >
          שלח תגובה
        </Link>
      </div>
      <Replies
        tid={t ?? "9"}
        forum={f ?? ""}
        replies={replies ?? []}
        current={tpage ?? "1"}
        total={total ?? 0}
        tdetails={tdetails ?? null}
      />
      <div className="flex my-8 text-white justify-between items-center w-full">
        <Link
          className="bg-sky-400 text-black py-2 px-4 rounded-lg"
          to={`/post/${f}/${t}`}
        >
          שלח תגובה
        </Link>
        <h3 className="text-2xl font-semibold"></h3>
      </div>
    </section>
  );
}
