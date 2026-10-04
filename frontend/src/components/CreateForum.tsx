import { useState } from "react";
import { createForum, type CreateForumData } from "../fetchMethods/createForum";
import { updateForum } from "../fetchMethods/updateForum";

type CreateForumProps = {
  setShowMenu: (value: boolean) => void;
  data?: CreateForumData;
};
export default function CreateForum({ setShowMenu, data }: CreateForumProps) {
  const [name, setName] = useState(data?.name ?? "");
  const id = data?.id ?? 1;
  const [description, setDescription] = useState(data?.description ?? "");
  const [sortOrder, setSortOrder] = useState(data?.sort_order ?? 1);
  const [loading, setLoading] = useState(false);
  const baseUrl = import.meta.env.BASE_URL;

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();

    try {
      setLoading(true);
      let forum;
      if (!data) {
        forum = await createForum({
          name,
          description,
          sort_order: sortOrder,
        });
        console.log("Created:", forum);
      } else {
        forum = await updateForum({
          id,
          name,
          description,
          sort_order: sortOrder,
        });
        console.log("Updated:", forum);
      }

      setName("");
      setDescription("");
      setSortOrder(1);
    } catch (error) {
      console.error(error);
    } finally {
      setLoading(false);
      setShowMenu(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      dir="rtl"
      className="bg-gray-500 p-4  z-20 rounded-xl fixed top-[50%] translate-x-[-50%] translate-y-[-50%] left-[50%] mx-auto mt-10 flex max-w-xl flex-col gap-2 "
    >
      <button className="cursor-pointer" onClick={() => setShowMenu(false)}>
        <img
          className="absolute top-2 left-2"
          src={`${baseUrl}close2.png`}
          alt=""
        />
      </button>

      <label className="text-white" htmlFor="name">
        שם הפורום
      </label>
      <input
        id="name"
        type="text"
        placeholder="שם הפורום"
        value={name}
        onChange={(e) => setName(e.target.value)}
        required
        className="rounded bg-slate-800 p-3 text-white"
      />

      <label className="text-white" htmlFor="description">
        תיאור הפורום
      </label>
      <textarea
        id="description"
        placeholder="תיאור"
        value={description}
        onChange={(e) => setDescription(e.target.value)}
        className="rounded bg-slate-800 p-3 text-white"
      />
      <label className="text-white" htmlFor="index">
        מספר הדירוג
      </label>
      <input
        id="index"
        type="number"
        min="1"
        value={sortOrder}
        onChange={(e) => setSortOrder(Number(e.target.value))}
        className="rounded bg-slate-800 p-3 text-white"
      />

      <button
        disabled={loading}
        className="rounded bg-cyan-500 p-3 font-bold text-black disabled:opacity-50"
      >
        {data
          ? loading
            ? "מעדכן.."
            : "עדכן פורום"
          : loading
            ? "יוצר.."
            : "צור פורום"}
      </button>
    </form>
  );
}
