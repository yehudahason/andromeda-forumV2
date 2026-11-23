import getToken from "../lib/getToken";

export async function updateProfileImage(imageUrl: string) {
  const accessToken = await getToken();
  const response = await fetch("https://api.pitron-halomot.org/api/me/image", {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      image_url: imageUrl,
    }),
  });

  if (!response.ok) {
    throw new Error("Failed to update profile image");
  }

  return response.json();
}
