import UploadImage from "../pages/UploadImage";
import { useRef, useEffect, useState } from "react";
import { useUserStore } from "../stores/userStore";
import { getUserByID } from "../fetchMethods/getUserByID";
import { useQuery } from "@tanstack/react-query";
type ProfileHeader = {
  userId: string | undefined;
  isThreads: boolean;
};

export default function ProfileHeader({ userId, isThreads }: ProfileHeader) {
  const [isOpen, setIsOpen] = useState(false);
  const divRef = useRef<HTMLDivElement>(null);
  const btnRef = useRef<HTMLButtonElement>(null);
  const { user } = useUserStore();

  const { data: userProfile } = useQuery({
    queryKey: ["userProfile", userId],

    queryFn: () => getUserByID(userId!),

    enabled: !!userId,

    staleTime: 300_000,
  });

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      const target = event.target as Node;

      if (
        divRef.current &&
        !divRef.current.contains(target) &&
        !btnRef.current?.contains(target)
      ) {
        setIsOpen(false);
      }
    }

    document.addEventListener("mousedown", handleClickOutside);

    return () => {
      document.removeEventListener("mousedown", handleClickOutside);
    };
  }, []);

  return (
    <div className="">
      <h1 className="text-2xl py-4 text-white font-bold">
        {userProfile?.name}
      </h1>
      <a
        className={`${isThreads ? "text-sky-500" : "text-white"} m-2 `}
        href={`/users/${userId}/threads`}
      >
        כל השירשורים
      </a>
      <a
        className={`${!isThreads ? "text-sky-500" : "text-white"} m-2 `}
        href={`/users/${userId}/replies`}
      >
        כל ההודעות
      </a>
      {user?.id === userId && (
        <button
          ref={btnRef}
          className="text-amber-200"
          onClick={() => setIsOpen((prev) => !prev)}
        >
          Upload Profile Image
        </button>
      )}

      {user?.id !== userId && (
        <a className="text-amber-300 mx-2" href={`/privatethread/${userId}`}>
          הודעה פרטית
        </a>
      )}

      {isOpen && (
        <div
          ref={divRef}
          className="w-72 fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2"
        >
          <UploadImage />
        </div>
      )}
    </div>
  );
}
