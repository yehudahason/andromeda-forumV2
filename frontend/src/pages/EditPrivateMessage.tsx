import PostComposer, { type Post } from "../components/PostComposer";
import AfterPost from "../components/AfterPost";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { editPrivateMessage } from "../fetchMethods/privateMessages";
import type { Dispatch, SetStateAction } from "react";

export type EditPrivateMessageProps = {
  t: number;
  id: number;
  page: number;
  content: string;
} & {
  setShowEdit?: Dispatch<SetStateAction<EditPrivateMessageProps | null>>;
};

export default function EditPrivateMessage({
  t,
  id,
  page,
  content,
  setShowEdit,
}: EditPrivateMessageProps) {
  const queryClient = useQueryClient();

  const updateReplyMutation = useMutation({
    mutationFn: (item: Post) => {
      if (!id) {
        throw new Error("Reply ID is missing");
      }
      if (!item.content) {
        throw new Error("Content  is missing");
      }

      return editPrivateMessage(id, item.content);
    },

    retry: false,

    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ["privateMessages", t, page],
      });
      setShowEdit?.(null);
    },

    onError: (error) => {
      console.error(error);
    },
  });

  //Direct Link back to msg
  if (updateReplyMutation.isSuccess) {
    // return (
    //   <AfterPost success={true} postLink={`/private/${t}?page=${page}#${id}`} />
    // );
  }

  if (updateReplyMutation.isError) {
    return <AfterPost success={false} postLink="" />;
  }
  if (!t) return;
  return (
    <PostComposer
      threadID={+t}
      post={{
        content,
        notify: true,
      }}
      mode="reply"
      disabled={updateReplyMutation.isPending}
      onSubmit={(item: Post) => {
        updateReplyMutation.mutate(item);
      }}
    />
  );
}
