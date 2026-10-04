export async function getReplyPosition(
  threadID: number,
  replyID: string,
): Promise<number> {
  const url = "https://api.pitron-halomot.org";

  const res = await fetch(`${url}/api/replies/${threadID}/${replyID}/position`);

  if (!res.ok) {
    const message = await res.text();
    throw new Error(message || "Failed to get reply position");
  }

  const data: { position: number } = await res.json();

  return data.position;
}
