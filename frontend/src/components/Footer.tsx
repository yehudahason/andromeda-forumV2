export default function Footer() {
  return (
    <footer className="mt-auto flex flex-col justify-end dark:bg-neutral-800 flex-1">
      <div className="p-4 text-center text-[0.9rem] tracking-[0.5px] text-[rgb(209,154,82)]">
        Coded by
        <a
          href="https://www.frontendmentor.io/profile/yehudahason"
          target="_blank"
          rel="noopener noreferrer"
          className="
            mx-1
            font-semibold
            text-[rgb(210,93,50)]
            no-underline
            hover:opacity-50
          "
        >
          @Yehuda Hason
        </a>
        <span className="mx-2 opacity-60" aria-hidden="true">
          •
        </span>
      </div>
    </footer>
  );
}
