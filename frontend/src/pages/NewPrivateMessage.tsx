import PostComposer, { type Post } from "../components/PostComposer";
import { sendPrivateMessage } from "../fetchMethods/privateMessages";
import { useParams } from "react-router-dom";
import AfterPost from "../components/AfterPost";
import { useMutation, useQueryClient } from "@tanstack/react-query";

export default function NewPrivateMessage() {
  const { tid } = useParams();
  const queryClient = useQueryClient();

  const createThreadMutation = useMutation({
    mutationFn: (item: Post) => {
      if (!tid) {
        throw new Error("Thread ID is missing");
      }

      return sendPrivateMessage(+tid, item.content ?? "");
    },

    onSuccess: () => {
      // Refresh replies for this thread
      queryClient.invalidateQueries({
        queryKey: ["threads", tid],
      });

      // Refresh thread details too
      queryClient.invalidateQueries({
        queryKey: ["getThread", tid],
      });
    },

    onError: (error) => {
      console.error(error);
    },
  });

  if (createThreadMutation.isSuccess) {
    const response = createThreadMutation.data;
    console.log(response);
    return <AfterPost success={true} postLink={`${tid}`} />;
  }

  if (createThreadMutation.isError) {
    return <AfterPost success={false} postLink="" />;
  }

  return (
    <PostComposer
      mode="reply"
      submitText="הודעה פרטית"
      disabled={createThreadMutation.isPending}
      onSubmit={(item: Post) => {
        if (createThreadMutation.isPending) return;

        createThreadMutation.mutate(item);
      }}
    />
  );
}
