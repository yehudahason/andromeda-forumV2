import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { followThread } from "../fetchMethods/followThread";
import { unFollowThread } from "../fetchMethods/unFollowThread";
import { isFollowThread } from "../fetchMethods/isFollowThread";

type FollowButtonProps = {
  threadID: number;
};

export default function FollowButton({ threadID }: FollowButtonProps) {
  const queryClient = useQueryClient();

  const queryKey = ["threadFollow", threadID];

  const {
    data: isFollowing = false,
    isLoading,
    isError,
  } = useQuery({
    queryKey,
    queryFn: () => isFollowThread(threadID),
    enabled: threadID > 0,
  });

  const mutation = useMutation({
    mutationFn: async (follow: boolean) => {
      if (follow) {
        await followThread(threadID);
      } else {
        await unFollowThread(threadID);
      }
    },

    onSuccess: async () => {
      await queryClient.invalidateQueries({
        queryKey,
      });
    },
  });

  const handleClick = () => {
    mutation.mutate(!isFollowing);
  };

  if (isLoading) {
    return (
      <button disabled className="px-4 py-2 rounded-lg bg-gray-600">
        טוען...
      </button>
    );
  }

  if (isError) {
    return null;
  }

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={mutation.isPending}
      className={`px-4 py-2 cursor-pointer rounded-lg font-medium transition-colors disabled:opacity-50 ${
        isFollowing
          ? "bg-gray-600 text-white hover:bg-gray-700"
          : "bg-sky-400 text-black hover:bg-sky-500"
      }`}
    >
      {mutation.isPending
        ? "מעדכן..."
        : isFollowing
          ? "בטל מעקב"
          : "עקוב אחרי הדיון"}
    </button>
  );
}
