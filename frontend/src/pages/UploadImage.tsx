import ImageUpload from "../components/ImageUpload";

import { updateProfileImage } from "../fetchMethods/updateProfileImage";
export default function UploadImage() {
  async function setImage(url: string) {
    try {
      await updateProfileImage(url);
      window.location.reload();
    } catch (e) {
      if (e instanceof Error) console.log(e.message);
    }
  }
  return (
    <div>
      <ImageUpload onUploaded={(url: string) => setImage(url)} />
    </div>
  );
}
