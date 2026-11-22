function isValidUTC(value: string): boolean {
  const date = new Date(value);

  if (Number.isNaN(date.getTime())) return false;

  return /(?:Z|[+-]\d{2}:\d{2})$/.test(value);
}

export function formatDate(dateString: string | null | undefined) {
  if (!dateString || !isValidUTC(dateString)) return "";

  const date = new Date(dateString);
  const now = new Date();

  const oneYear = new Date(now);
  oneYear.setFullYear(now.getFullYear() - 1);

  const pad = (value: number) => String(value).padStart(2, "0");

  // Same calendar day → HH:MM
  const isToday =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();

  if (isToday) {
    return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }
  // DD-MM-YY
  return `${pad(date.getDate())}-${pad(date.getMonth() + 1)}-${String(date.getFullYear()).slice(-2)}`;

  // Older than one year → DD-MM-YY
  // if (date < oneYear) {
  //   return `${pad(date.getDate())}-${pad(date.getMonth() + 1)}-${String(date.getFullYear()).slice(-2)}`;
  // }

  // Otherwise → DD-MM
  // return `${pad(date.getDate())}-${pad(date.getMonth() + 1)}`;
}
