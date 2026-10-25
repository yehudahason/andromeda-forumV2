import type { HTMLAttributes } from "react";

interface HtmlContentProps extends HTMLAttributes<HTMLDivElement> {
  html: string;
}

export default function HtmlContent({
  html,
  className = "",
  ...props
}: HtmlContentProps) {
  return (
    <div
      {...props}
      className={`
        [&_a]:text-sky-400
        [&_a]:underline

        [&_ul]:list-disc
        [&_ul]:ps-6
        [&_ul]:list-outside

        [&_ol]:list-decimal
        [&_ol]:ps-6
        [&_ol]:list-outside

        [&_li]:my-1

        w-full
        max-w-full
        min-w-0
        overflow-hidden

        [&>div]:w-full
        [&>div]:max-w-full
        [&>div]:min-w-0

        [&_pre]:w-full
        [&_pre]:max-w-full
        [&_pre]:min-w-0
        [&_pre]:overflow-x-auto
        [&_pre]:whitespace-pre

        [&_code]:block
        [&_code]:max-w-full
        [&_code]:min-w-0
        [&_code]:[direction:ltr]

        ${className}
      `}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
