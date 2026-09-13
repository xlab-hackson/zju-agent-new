/**
 * 浙大校园常识知识库（CC98《浙江大学本科新生指引》，见 knowledge/ATTRIBUTION.md）。
 *
 * 数据以 markdown 文件形式随包分发，首次使用时懒加载并常驻内存：
 * - 系统提示词只放「章节大纲」（getGuideOutline），不塞全文；
 * - Agent 按需调用 zju_search_guide / zju_read_guide 取原文片段。
 *
 * 目录解析顺序：ZJU_AGENT_KNOWLEDGE_DIR 环境变量 → 同级 knowledge/（esbuild 打包后）
 * → 上两级 knowledge/（tsx 源码 / tsc 产物）。任一命中即用，全部落空时降级为空知识库，
 * 不影响其它功能。
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { AppError, ErrorCode } from "@zju-agent/core";
import { logger } from "../config/logger.js";
import {
  buildDocumentFrequency,
  extractDocTitle,
  searchSections,
  splitIntoSections,
  type GuideSection,
} from "./search.js";

export type { GuideSection } from "./search.js";

/** 一级目录名 → 章节中文名 */
const CHAPTER_NAMES: Record<string, string> = {
  basics: "常用信息",
  registration: "报到",
  military_training: "军训",
  learning: "学习",
  course_sys: "选课",
  "awards&grants": "奖助",
  life: "生活",
  dorms: "园区",
  cc98: "CC98论坛",
  haining: "海宁国际校区",
  HK_Macao_Taiwan: "港澳台生",
};

/** 章节在大纲里的展示顺序（未列出的一律排在末尾） */
const CHAPTER_ORDER = [...Object.values(CHAPTER_NAMES), "其他"];

const FALLBACK_CHAPTER = "其他";
/** 站点元信息与说明文件，不进入检索索引 */
const SKIP_DOCS = new Set([
  "index.md",
  "preface.md",
  "postscript.md",
  "README.md",
  "ATTRIBUTION.md",
]);

/** zju_search_guide 单条结果的最大长度 */
export const SEARCH_SNIPPET_CHARS = 1500;
/** zju_read_guide 单篇文档的最大长度 */
export const READ_DOC_CHARS = 8000;

export type GuideDocument = {
  doc: string;
  chapter: string;
  title: string;
  text: string;
};

export type GuideIndex = {
  root: string;
  docs: Map<string, GuideDocument>;
  sections: GuideSection[];
  /** IDF 统计，首次检索时懒构建 */
  df: Map<string, number> | null;
};

let cached: GuideIndex | null = null;
let loadFailed = false;

/** 清空缓存（单测用） */
export function resetGuideCache(): void {
  cached = null;
  loadFailed = false;
}

/** 定位知识库目录；找不到返回 null */
export function resolveGuideRoot(): string | null {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const candidates = [
    process.env.ZJU_AGENT_KNOWLEDGE_DIR?.trim(),
    path.resolve(here, "knowledge"), // esbuild 打包：dist/server/knowledge
    path.resolve(here, "../../knowledge"), // tsx 源码 / tsc 产物：packages/server/knowledge
  ].filter((dir): dir is string => Boolean(dir));

  for (const dir of candidates) {
    if (!fs.existsSync(dir)) continue;
    if (collectMarkdownFiles(dir).length > 0) return dir;
  }
  return null;
}

function collectMarkdownFiles(dir: string, prefix = ""): Array<{ doc: string; file: string }> {
  const out: Array<{ doc: string; file: string }> = [];
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }

  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name.startsWith(".")) continue;
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      if (entry.name === "stylesheets") continue;
      out.push(...collectMarkdownFiles(path.join(dir, entry.name), rel));
      continue;
    }
    if (!entry.isFile() || !entry.name.endsWith(".md") || SKIP_DOCS.has(rel)) continue;
    out.push({ doc: rel, file: path.join(dir, entry.name) });
  }
  return out;
}

function chapterOf(doc: string): string {
  const top = doc.includes("/") ? doc.slice(0, doc.indexOf("/")) : "";
  return CHAPTER_NAMES[top] ?? FALLBACK_CHAPTER;
}

/** 懒加载并缓存知识库索引；目录缺失时返回 null（只告警一次） */
export function loadGuideIndex(): GuideIndex | null {
  if (cached) return cached;
  if (loadFailed) return null;

  const root = resolveGuideRoot();
  if (!root) {
    loadFailed = true;
    logger.warn("未找到知识库目录，校园常识检索工具将不可用", {
      hint: "可用 ZJU_AGENT_KNOWLEDGE_DIR 指向 knowledge 目录",
    });
    return null;
  }

  const docs = new Map<string, GuideDocument>();
  const sections: GuideSection[] = [];

  for (const { doc, file } of collectMarkdownFiles(root)) {
    let content: string;
    try {
      content = fs.readFileSync(file, "utf8");
    } catch (err) {
      logger.warn("知识库文件读取失败", {
        doc,
        message: err instanceof Error ? err.message : String(err),
      });
      continue;
    }
    const chapter = chapterOf(doc);
    const docSections = splitIntoSections(doc, chapter, content);
    if (docSections.length === 0) continue; // 纯图片/附件类文档，跳过
    docs.set(doc, {
      doc,
      chapter,
      title: extractDocTitle(content) || docSections[0]!.title || path.basename(doc, ".md"),
      text: content.trim(),
    });
    sections.push(...docSections);
  }

  cached = { root, docs, sections, df: null };
  logger.info("知识库已加载", { root, docs: docs.size, sections: sections.length });
  return cached;
}

export type GuideSearchHit = {
  doc: string;
  chapter: string;
  section: string;
  text: string;
};

/** 检索知识库，返回按相关度排序的原文片段 */
export function searchGuide(query: string, limit = 4): GuideSearchHit[] {
  const index = loadGuideIndex();
  if (!index) return [];

  index.df ??= buildDocumentFrequency(index.sections);

  return searchSections(index.sections, query, limit, index.df).map((section) => ({
    doc: section.doc,
    chapter: section.chapter,
    section: section.breadcrumb.join(" > "),
    text:
      section.text.length > SEARCH_SNIPPET_CHARS
        ? `${section.text.slice(0, SEARCH_SNIPPET_CHARS)}…（片段已截断，可用 zju_read_guide 读取全文）`
        : section.text,
  }));
}

export type GuideDocContent = {
  doc: string;
  chapter: string;
  title: string;
  text: string;
  truncated: boolean;
};

/** 按路径读取知识库全文；路径不存在时抛 AppError */
export function readGuideDoc(rawDoc: string): GuideDocContent {
  const index = loadGuideIndex();
  if (!index) {
    throw new AppError(
      ErrorCode.ZJU_SERVICE_UNAVAILABLE,
      "知识库未加载：未找到知识库目录。",
    );
  }

  const normalized = rawDoc.trim().replace(/\\/g, "/").replace(/^\.\//, "");
  const key = index.docs.has(normalized)
    ? normalized
    : [...index.docs.keys()].find((doc) => doc.toLowerCase() === normalized.toLowerCase());

  const doc = key ? index.docs.get(key) : undefined;
  if (!doc) {
    throw new AppError(
      ErrorCode.TOOL_INPUT_INVALID,
      `知识库中不存在文档「${rawDoc}」。可用路径见 zju_search_guide 返回结果中的 doc 字段。`,
    );
  }

  return {
    doc: doc.doc,
    chapter: doc.chapter,
    title: doc.title,
    text:
      doc.text.length > READ_DOC_CHARS
        ? `${doc.text.slice(0, READ_DOC_CHARS)}\n…（文档过长已截断）`
        : doc.text,
    truncated: doc.text.length > READ_DOC_CHARS,
  };
}

/**
 * 生成给系统提示词用的章节目录（按章节聚合文档标题）。
 * 知识库缺失时返回空串，提示词会整体省略知识库段落。
 */
export function getGuideOutline(): string {
  const index = loadGuideIndex();
  if (!index) return "";

  const byChapter = new Map<string, string[]>();
  for (const doc of index.docs.values()) {
    const list = byChapter.get(doc.chapter) ?? [];
    list.push(doc.title);
    byChapter.set(doc.chapter, list);
  }

  return CHAPTER_ORDER.filter((chapter) => byChapter.has(chapter))
    .map((chapter) => `- ${chapter}：${byChapter.get(chapter)!.join("、")}`)
    .join("\n");
}
