import { useParams } from "react-router-dom";
import PostComposer from "../components/PostComposer";
import type { Post } from "../components/PostComposer";
import { createReply } from "../fetchMethods/createReply";
import AfterPost from "../components/AfterPost";
import { useMutation, useQueryClient } from "@tanstack/react-query";

export default function NewReply() {
  const { f, t } = useParams();
  const queryClient = useQueryClient();

  const createReplyMutation = useMutation({
    mutationFn: (item: Post) => {
      if (!f || !t) {
        throw new Error("Forum ID or thread ID is missing");
      }

      return createReply(item, Number(f), Number(t));
    },

    onSuccess: () => {
      // Refresh replies for this thread
      queryClient.invalidateQueries({
        queryKey: ["threads", f, t],
      });

      // Refresh thread details too
      queryClient.invalidateQueries({
        queryKey: ["getThread", f, t],
      });
    },

    onError: (error) => {
      console.error(error);
    },
  });

  if (createReplyMutation.isSuccess) {
    return <AfterPost success={true} postLink={createReplyMutation.data} />;
  }

  if (createReplyMutation.isError) {
    return <AfterPost success={false} postLink="" />;
  }

  return (
    <PostComposer
      mode="reply"
      disabled={createReplyMutation.isPending}
      onSubmit={(item: Post) => {
        if (createReplyMutation.isPending) return;

        createReplyMutation.mutate(item);
      }}
    />
  );
}
