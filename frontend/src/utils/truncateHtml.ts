export function truncateHtml(html: string, maxChars = 200) {
  const doc = new DOMParser().parseFromString(html, "text/html");
  let count = 0;
  let finished = false;

  function walk(node: Node) {
    if (finished) {
      node.parentNode?.removeChild(node);
      return;
    }

    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent ?? "";
      const remaining = maxChars - count;

      if (text.length > remaining) {
        node.textContent = text.slice(0, remaining) + "...";
        finished = true;
        return;
      }

      count += text.length;
      return;
    }

    for (const child of Array.from(node.childNodes)) {
      walk(child);
    }
  }

  walk(doc.body);

  return doc.body.innerHTML;
}
