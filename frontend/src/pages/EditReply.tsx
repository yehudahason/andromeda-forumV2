import PostComposer, { type Post } from "../components/PostComposer";
import { updateReply } from "../fetchMethods/updateReply";
import { getReplyByID } from "../fetchMethods/getReplyByID";
import { useParams } from "react-router-dom";
import AfterPost from "../components/AfterPost";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { ReplyPost } from "../types";
import { getReplyPosition } from "../fetchMethods/getReplyPosition";

export default function EditReply() {
  const { f, t, id } = useParams();
  const queryClient = useQueryClient();

  const {
    data: reply,
    isLoading: isReplyLoading,
    isError: isReplyError,
  } = useQuery<ReplyPost>({
    queryKey: ["reply", id],
    queryFn: () => getReplyByID(id!),
    enabled: !!id,
  });

  const {
    data: position,
    isLoading: isPositionLoading,
    isError: isPositionError,
  } = useQuery({
    queryKey: ["replyPosition", t, id],
    queryFn: () => getReplyPosition(Number(t), id!),
    enabled: !!t && !!id,
  });

  const page = position != null ? Math.ceil(position / 14) : 1;

  const updateReplyMutation = useMutation({
    mutationFn: (item: Post) => {
      if (!id) {
        throw new Error("Reply ID is missing");
      }

      return updateReply(item, id);
    },

    retry: false,

    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["threads", f],
      });

      queryClient.invalidateQueries({
        queryKey: ["getThread", f, t],
      });

      queryClient.invalidateQueries({
        queryKey: ["reply", id],
      });
    },

    onError: (error) => {
      console.error(error);
    },
  });

  if (isReplyLoading || isPositionLoading) {
    return <div className="text-center my-8 text-amber-200">Loading...</div>;
  }

  if (isReplyError || isPositionError || !reply) {
    return <AfterPost success={false} postLink="" />;
  }

  if (updateReplyMutation.isSuccess) {
    return (
      <AfterPost
        success={true}
        postLink={`/forum/${f}/${t}?tpage=${page}#${id}`}
      />
    );
  }

  if (updateReplyMutation.isError) {
    return <AfterPost success={false} postLink="" />;
  }

  return (
    <PostComposer
      post={{
        title: "",
        content: reply.post,
        notify: reply.notify,
      }}
      mode="reply"
      disabled={updateReplyMutation.isPending}
      onSubmit={(item: Post) => {
        updateReplyMutation.mutate(item);
      }}
    />
  );
}
