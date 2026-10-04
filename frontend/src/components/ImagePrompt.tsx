import { useState } from "react";

type ImagePromptProps = {
  open: boolean;
  onClose: () => void;
  onSubmit: (url: string) => void;
};

export default function ImagePrompt({
  open,
  onClose,
  onSubmit,
}: ImagePromptProps) {
  const [url, setUrl] = useState("");

  if (!open) return null;

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    const trimmed = url.trim();
    if (!trimmed) return;
    console.log(trimmed);

    onSubmit(trimmed);
    setUrl("");
    onClose();
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-md rounded-lg bg-gray-800 p-4"
        dir="rtl"
      >
        <label className="mb-2 block text-sm text-gray-200">
          הכנס קישור לתמונה
        </label>

        <input
          type="url"
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          autoFocus
          placeholder="https://example.com/image.jpg"
          className="w-full rounded border border-gray-600 bg-gray-900 px-3 py-2 text-white outline-none focus:border-cyan-400"
        />

        <div className="mt-4 flex gap-2">
          <button
            type="submit"
            className="rounded bg-cyan-600 px-4 py-2 text-white"
          >
            הוסף
          </button>

          <button
            type="button"
            onClick={() => {
              setUrl("");
              onClose();
            }}
            className="rounded bg-gray-600 px-4 py-2 text-white"
          >
            ביטול
          </button>
        </div>
      </form>
    </div>
  );
}
