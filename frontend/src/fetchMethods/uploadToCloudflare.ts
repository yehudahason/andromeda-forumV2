import { getAuthToken } from "../lib/getAuthToken";

type UploadResponse = {
  url: string;
};
export async function uploadToCloudFlare(formData: FormData) {
  const token = await getAuthToken();
  const response = await fetch("https://api.pitron-halomot.org/api/upload", {
    method: "POST",

    headers: {
      Authorization: `Bearer ${token}`,
    },

    body: formData,
  });

  if (!response.ok) {
    const text = await response.text();

    throw new Error(text || `Upload failed: ${response.status}`);
  }

  const data: UploadResponse = await response.json();
  return data;
}
