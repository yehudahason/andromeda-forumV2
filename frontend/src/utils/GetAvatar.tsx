type AvatarProps = {
  name: string;
  image: string | null;
  size: number;
};

export function GetAvatar({ name, image, size }: AvatarProps) {
  if (!name) return null;

  const avatarStyle = {
    width: `${size}px`,
    height: `${size}px`,
    minWidth: `${size}px`,
    minHeight: `${size}px`,
  };

  if (image) {
    return (
      <img
        src={image}
        alt={name}
        style={avatarStyle}
        className="shrink-0 rounded-full object-cover"
      />
    );
  }

  const colors = [
    "bg-red-500",
    "bg-blue-500",
    "bg-green-500",
    "bg-yellow-500",
    "bg-purple-500",
    "bg-pink-500",
    "bg-indigo-500",
    "bg-orange-500",
  ];

  const index =
    [...name].reduce((sum, char) => sum + char.charCodeAt(0), 0) %
    colors.length;

  const letter = [...name.trim()][0]?.toUpperCase() ?? "?";

  return (
    <div
      style={avatarStyle}
      className={`${colors[index]} shrink-0 rounded-full flex items-center justify-center text-white text-sm font-semibold`}
      aria-label={name}
    >
      {letter}
    </div>
  );
}
