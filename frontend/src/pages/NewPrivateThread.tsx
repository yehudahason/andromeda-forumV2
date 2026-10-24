import PostComposer, { type Post } from "../components/PostComposer";
import { createPrivateThread } from "../fetchMethods/privateMessages";
import { useParams } from "react-router-dom";
import AfterPost from "../components/AfterPost";
import { useMutation, useQueryClient } from "@tanstack/react-query";

export default function NewPrivateThread() {
  const { userid } = useParams();
  const queryClient = useQueryClient();

  const createThreadMutation = useMutation({
    mutationFn: (item: Post) => {
      if (typeof userid !== "string") {
        throw new Error("User ID is missing");
      }

      return createPrivateThread({
        title: item.title,
        content: item.content ?? "",
        participant_ids: [userid],
      });
    },

    onSuccess: () => {
      // Refresh replies for this thread
      queryClient.invalidateQueries({
        queryKey: ["threads", userid],
      });

      // Refresh thread details too
      queryClient.invalidateQueries({
        queryKey: ["getThread", userid],
      });
    },

    onError: (error) => {
      console.error(error);
    },
  });

  if (createThreadMutation.isSuccess) {
    const response = createThreadMutation.data;
    console.log(response);
    return <AfterPost success={true} postLink={`${userid}`} />;
  }

  if (createThreadMutation.isError) {
    return <AfterPost success={false} postLink="" />;
  }

  return (
    <PostComposer
      mode="thread"
      submitText="הודעה פרטית"
      disabled={createThreadMutation.isPending}
      onSubmit={(item: Post) => {
        if (createThreadMutation.isPending) return;

        createThreadMutation.mutate(item);
      }}
    />
  );
}
