import PostComposer, { type Post } from "../components/PostComposer";
import { updateThread } from "../fetchMethods/updateThread";
import { useParams } from "react-router-dom";
import AfterPost from "../components/AfterPost";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { getThreadByID } from "../fetchMethods/getThreadByID";
import type { ThreadDetails } from "../types";

export default function EditThread() {
  const { f, t } = useParams();

  const queryClient = useQueryClient();

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ["getThread", f, t],
    queryFn: () => getThreadByID(Number(t), Number(f)),
    enabled: !!t && !!f,
  });

  const updateThreadMutation = useMutation({
    mutationFn: (item: Post) => {
      if (!t) {
        throw new Error("Thread ID is missing");
      }

      return updateThread(item, Number(t));
    },

    retry: false,

    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["threads", f],
      });

      queryClient.invalidateQueries({
        queryKey: ["getThread", f, t],
      });
    },

    onError: (error) => {
      console.error(error);
    },
  });

  const tdetails: ThreadDetails | undefined = data;

  if (isError) {
    return <h3 className="text-red-500 text-center py-8">{error.message}</h3>;
  }

  if (updateThreadMutation.isSuccess) {
    return <AfterPost success={true} postLink={`/forum/${f}/${t}`} />;
  }

  if (updateThreadMutation.isError) {
    return <AfterPost success={false} postLink="" />;
  }

  if (isLoading) {
    return <h3 className="text-amber-300 text-center py-8">המתן..</h3>;
  }

  return (
    <PostComposer
      post={{
        title: tdetails?.title,
        content: tdetails?.content,
        notify: false,
      }}
      mode="thread"
      disabled={updateThreadMutation.isPending}
      onSubmit={(item: Post) => {
        updateThreadMutation.mutate(item);
      }}
    />
  );
}
