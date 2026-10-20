import PostComposer, { type Post } from "../components/PostComposer";
import { createThread } from "../fetchMethods/createThread";
import { useParams } from "react-router-dom";
import AfterPost from "../components/AfterPost";
import { useMutation, useQueryClient } from "@tanstack/react-query";

export default function NewThread() {
  const { f } = useParams();
  const queryClient = useQueryClient();

  const createThreadMutation = useMutation({
    mutationFn: (item: Post) => {
      if (!f) {
        throw new Error("Forum ID is missing");
      }

      return createThread(item, Number(f));
    },

    onSuccess: () => {
      // Refresh replies for this thread
      queryClient.invalidateQueries({
        queryKey: ["threads", f],
      });

      // Refresh thread details too
      queryClient.invalidateQueries({
        queryKey: ["getThread", f],
      });
    },

    onError: (error) => {
      console.error(error);
    },
  });

  if (createThreadMutation.isSuccess) {
    const response = createThreadMutation.data;

    return (
      <AfterPost
        success={true}
        postLink={`/forum/${response?.forum_id}/${response?.id}`}
      />
    );
  }

  if (createThreadMutation.isError) {
    return <AfterPost success={false} postLink="" />;
  }

  return (
    <PostComposer
      mode="thread"
      disabled={createThreadMutation.isPending}
      onSubmit={(item: Post) => {
        if (createThreadMutation.isPending) return;

        createThreadMutation.mutate(item);
      }}
    />
  );
}
