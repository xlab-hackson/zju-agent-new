/**
 * 富文本消毒：用 DOMParser 解析后按白名单重建 DOM。
 * - 只保留常见排版标签（p/br/b/ul/li/a/img/…）
 * - 只保留 a[href] 与 img[src]，且仅 http/https/mailto 协议
 * - 剥离所有事件属性、style、script/iframe 等
 * DOMParser 生成的文档是惰性的（脚本不会执行），重建过程安全。
 */

const ALLOWED_TAGS = new Set([
  "p", "br", "hr",
  "b", "strong", "i", "em", "u", "s",
  "span", "div",
  "ul", "ol", "li",
  "h1", "h2", "h3", "h4", "h5", "h6",
  "blockquote", "code", "pre",
  "a", "img",
  "table", "thead", "tbody", "tr", "td", "th",
]);

const URL_ATTRS: Record<string, string[]> = {
  a: ["href"],
  img: ["src"],
};

export function sanitizeHtml(input: string): string {
  if (!input) return "";
  try {
    const doc = new DOMParser().parseFromString(input, "text/html");
    const out = doc.createElement("div");
    for (const node of Array.from(doc.body.childNodes)) {
      out.appendChild(sanitizeNode(node, doc));
    }
    return out.innerHTML;
  } catch {
    return escapeText(input);
  }
}

function sanitizeNode(node: Node, doc: Document): Node {
  if (node.nodeType === Node.TEXT_NODE) {
    return doc.createTextNode(node.textContent ?? "");
  }
  if (node.nodeType !== Node.ELEMENT_NODE) {
    return doc.createTextNode("");
  }
  const el = node as Element;
  const tag = el.tagName.toLowerCase();
  if (!ALLOWED_TAGS.has(tag)) {
    // 移除不允许的元素但保留其文本内容，避免丢正文
    const frag = doc.createDocumentFragment();
    for (const child of Array.from(el.childNodes)) {
      frag.appendChild(sanitizeNode(child, doc));
    }
    return frag;
  }
  const clean = doc.createElement(tag);
  for (const attr of URL_ATTRS[tag] ?? []) {
    const value = el.getAttribute(attr);
    if (value && isSafeUrl(value)) {
      clean.setAttribute(attr, value);
    }
  }
  for (const child of Array.from(el.childNodes)) {
    clean.appendChild(sanitizeNode(child, doc));
  }
  return clean;
}

function isSafeUrl(value: string): boolean {
  const v = value.trim();
  if (/^javascript:/i.test(v) || /^vbscript:/i.test(v) || /^data:/i.test(v)) {
    return false;
  }
  try {
    const u = new URL(v, window.location.href);
    return (
      u.protocol === "http:" ||
      u.protocol === "https:" ||
      u.protocol === "mailto:"
    );
  } catch {
    return false;
  }
}

function escapeText(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
