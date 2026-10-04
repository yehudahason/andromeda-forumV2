import CreateForum from "../components/CreateForum";
import ForumList from "../components/ForumList";
import { getForums } from "../fetchMethods/getForums";
import type { ForumType } from "../types";
import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import type { CreateForumData } from "../fetchMethods/createForum";

export default function Home() {
  const [showMenu, setShowMenu] = useState<boolean>(false);
  const [dataU, setDataU] = useState<CreateForumData | undefined>();
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["forums", showMenu],
    queryFn: () => getForums(),
  });

  const baseUrl = import.meta.env.BASE_URL;
  const forums: ForumType[] | undefined = data;
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
        <h3 className="text-2xl font-semibold">פורומים</h3>
        <button
          onClick={() => {
            setDataU(undefined);
            setShowMenu((prev) => !prev);
          }}
          className="cursor-pointer"
        >
          <img src={`${baseUrl}add.png`} alt="" />
        </button>
      </div>
      {showMenu && <CreateForum data={dataU} setShowMenu={setShowMenu} />}
      <ForumList
        setShowMenu={setShowMenu}
        setDataU={setDataU}
        forums={forums ?? []}
      />
    </section>
  );
}
