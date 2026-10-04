import type { ChangeEvent } from "react";
import { useState, useEffect } from "react";
import { uploadToCloudFlare } from "../fetchMethods/uploadToCloudflare";

type ImageUploadProps = {
  onUploaded?: (url: string) => void;
};

export default function ImageUpload({ onUploaded }: ImageUploadProps) {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);

  const [uploading, setUploading] = useState(false);
  const [uploadedUrl, setUploadedUrl] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleFileChange = (e: ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];

    setError(null);
    setUploadedUrl(null);

    if (!selectedFile) {
      setFile(null);
      return;
    }

    // Validate type.
    if (!selectedFile.type.startsWith("image/")) {
      setError("יש לבחור קובץ תמונה");
      setFile(null);
      return;
    }

    // 5 MB limit.
    if (selectedFile.size > 5 * 1024 * 1024) {
      setError("גודל התמונה המקסימלי הוא 5MB");
      setFile(null);
      return;
    }

    setFile(selectedFile);
  };

  useEffect(() => {
    if (!file) {
      init(null);
      return;
    }

    async function init(val: string | null) {
      setPreview(val);
    }

    const objectUrl = URL.createObjectURL(file);

    init(objectUrl);

    return () => {
      URL.revokeObjectURL(objectUrl);
    };
  }, [file]);

  const handleUpload = async (e: React.SubmitEvent) => {
    e.preventDefault();

    if (!file) {
      setError("בחר תמונה");
      return;
    }

    setUploading(true);
    setError(null);

    try {
      const formData = new FormData();

      formData.append("image", file);

      const data = await uploadToCloudFlare(formData);

      setUploadedUrl(data.url);

      onUploaded?.(data.url);
    } catch (err) {
      if (err instanceof Error) {
        setError(err.message);
      } else {
        setError("העלאת התמונה נכשלה");
      }
    } finally {
      setUploading(false);
    }
  };

  const handleRemove = () => {
    setFile(null);
    setPreview(null);
    setUploadedUrl(null);
    setError(null);
  };

  return (
    <form
      onSubmit={handleUpload}
      dir="rtl"
      className="w-full max-w-md space-y-4 rounded-lg bg-neutral-800 p-5 text-white"
    >
      <label
        htmlFor="image-upload"
        className="block cursor-pointer rounded-md border border-dashed border-neutral-500 p-6 text-center transition hover:border-cyan-400"
      >
        <span className="block text-lg font-medium">בחר תמונה</span>

        <span className="mt-2 block text-sm text-neutral-400">
          JPG, PNG, WebP עד 5MB
        </span>

        <input
          id="image-upload"
          type="file"
          accept="image/jpeg,image/png,image/webp,image/gif"
          onChange={handleFileChange}
          className="hidden"
        />
      </label>

      {preview && (
        <div className="space-y-3">
          <img
            src={preview}
            alt="תצוגה מקדימה"
            className="max-h-72 w-full rounded-md object-contain"
          />

          <div className="text-sm text-neutral-300">{file?.name}</div>
        </div>
      )}

      {error && (
        <div className="rounded-md bg-red-950 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      {uploadedUrl && (
        <div className="rounded-md bg-green-950 p-3 text-sm text-green-300">
          התמונה הועלתה בהצלחה
        </div>
      )}

      <div className="flex gap-3">
        <button
          type="submit"
          disabled={!file || uploading}
          className="rounded-md bg-cyan-600 px-5 py-2 font-medium disabled:cursor-not-allowed disabled:opacity-50"
        >
          {uploading ? "מעלה..." : "העלה תמונה"}
        </button>

        {file && (
          <button
            type="button"
            onClick={handleRemove}
            disabled={uploading}
            className="rounded-md bg-neutral-700 px-5 py-2"
          >
            הסר
          </button>
        )}
      </div>
    </form>
  );
}
