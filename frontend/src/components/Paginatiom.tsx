import { useMemo } from "react";

type PaginationProps = {
  total: number;
  currentPage: number;
  onPageChange: (page: number) => void;
};

const PER_PAGE = 14;

export default function Pagination({
  total,
  currentPage,
  onPageChange,
}: PaginationProps) {
  const totalPages = Math.ceil(total / PER_PAGE);

  const pages = useMemo(() => {
    if (totalPages <= 7) {
      return Array.from({ length: totalPages }, (_, i) => i + 1);
    }

    if (currentPage <= 4) {
      return [1, 2, 3, 4, 5, "...", totalPages];
    }

    if (currentPage >= totalPages - 3) {
      return [
        1,
        "...",
        totalPages - 4,
        totalPages - 3,
        totalPages - 2,
        totalPages - 1,
        totalPages,
      ];
    }

    return [
      1,
      "...",
      currentPage - 1,
      currentPage,
      currentPage + 1,
      "...",
      totalPages,
    ];
  }, [currentPage, totalPages]);

  if (totalPages <= 1) return null;

  return (
    <nav
      dir="rtl"
      className="flex flex-col items-center gap-3 px-2 py-4 text-white sm:flex-row sm:justify-between sm:px-6"
    >
      {/* Page info */}
      <div className="flex items-center gap-2 text-sm">
        <span>עמוד</span>
        <span className="font-bold">{currentPage}</span>
        <span>מתוך</span>
        <span className="font-bold">{totalPages}</span>
      </div>

      {/* Pages */}
      <div className="flex items-center gap-1 sm:gap-2">
        {/* Previous */}
        <button
          type="button"
          disabled={currentPage === 1}
          onClick={() => onPageChange(currentPage - 1)}
          className="cursor-pointer px-2 py-2 text-xl disabled:cursor-not-allowed disabled:opacity-30 sm:px-3"
        >
          «
        </button>

        {pages.map((page, index) =>
          page === "..." ? (
            <span
              key={`ellipsis-${index}`}
              className="px-1 text-gray-400 sm:px-2"
            >
              ...
            </span>
          ) : (
            <button
              key={page}
              type="button"
              onClick={() => onPageChange(+page)}
              className={`min-w-8 cursor-pointer rounded-md px-2 py-2 text-sm font-semibold transition sm:min-w-9 sm:px-3 ${
                currentPage === page ? "bg-[#3b414b]" : "hover:bg-[#292d33]"
              }`}
            >
              {page}
            </button>
          ),
        )}

        {/* Next */}
        <button
          type="button"
          disabled={currentPage === totalPages}
          onClick={() => onPageChange(currentPage + 1)}
          className="cursor-pointer px-2 py-2 text-xl disabled:cursor-not-allowed disabled:opacity-30 sm:px-3"
        >
          »
        </button>
      </div>
    </nav>
  );
}
