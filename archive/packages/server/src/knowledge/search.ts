/**
 * 知识库检索的纯函数部分：markdown 分块 → 中文分词 → 打分排序。
 *
 * 数据加载与缓存见 index.ts，单测见 search.test.ts。
 * 不引入分词依赖：中文按 2-gram 切分，英文/数字按词切分，
 * 对 74 万字的语料足够，且完全离线、零依赖。
 */

export type GuideSection = {
  /** 稳定 id：doc#序号（同一文档内按出现顺序） */
  id: string;
  /** 相对知识库根目录的路径，如 "course_sys/rules.md" */
  doc: string;
  /** 章节中文名，如 "选课" */
  chapter: string;
  /** 标题链，如 ["选课规则", "抽签机制"] */
  breadcrumb: string[];
  /** 段落标题（breadcrumb 最后一项） */
  title: string;
  /** 原始 markdown 片段（回喂给模型时保留格式） */
  text: string;
  /** 归一化后的检索用文本 */
  plain: string;
  /** 归一化后的标题链（检索时命中权重更高） */
  titlePlain: string;
};

const HEADING_RE = /^(#{1,6})\s+(.+?)\s*$/;
/** 归一化后短于该长度的段落视为无信息（纯标题、纯图片、纯目录链接） */
const MIN_SECTION_CHARS = 10;
/** 单个 token 在正文中的计数上限，避免长文档靠词频刷分 */
const MAX_TERM_HITS = 6;
/** 单次检索最多切出的 token 数 */
const MAX_QUERY_TOKENS = 60;

/** 标题清洗：去掉图片/链接语法，保留可读文字 */
export function cleanTitle(raw: string): string {
  return raw
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/`/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** 归一化：去 markdown 装饰、统一小写，用于匹配（正文与查询共用） */
export function normalizeForSearch(input: string): string {
  return input
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/`{1,3}/g, " ")
    .replace(/^\s{0,3}>+\s?/gm, " ")
    .replace(/[#*_~|>]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

/**
 * 取文档标题：优先第一个 H1，没有 H1 时退回第一个任意级标题。
 * H1 通常没有正文、会被分块逻辑丢弃，所以单独抽取，用于大纲与 zju_read_guide 的展示。
 */
export function extractDocTitle(content: string): string {
  const source = content.replace(/^\uFEFF/, "");
  const h1 = /^#\s+(.+?)\s*$/m.exec(source);
  if (h1) return cleanTitle(h1[1]!);
  const anyHeading = /^#{1,6}\s+(.+?)\s*$/m.exec(source);
  return anyHeading ? cleanTitle(anyHeading[1]!) : "";
}

/**
 * 把一篇 markdown 按标题切成段落。
 * 每个标题开启一个段落，正文截止到下一个任意级别的标题；
 * 标题链（breadcrumb）保证子段落脱离父标题也能被理解。
 */
export function splitIntoSections(
  doc: string,
  chapter: string,
  content: string,
): GuideSection[] {
  // 部分源文件带 UTF-8 BOM，会让首个标题无法识别
  const lines = content.replace(/^\uFEFF/, "").split(/\r?\n/);
  const sections: GuideSection[] = [];
  const stack: Array<{ level: number; title: string }> = [];
  let current: {
    title: string;
    breadcrumb: string[];
    body: string[];
  } | null = null;

  const flush = () => {
    if (!current) return;
    const text = current.body.join("\n").trim();
    const plain = normalizeForSearch(text);
    if (plain.length >= MIN_SECTION_CHARS) {
      const breadcrumb = current.breadcrumb;
      sections.push({
        id: `${doc}#${sections.length + 1}`,
        doc,
        chapter,
        breadcrumb,
        title: current.title,
        text,
        plain,
        titlePlain: normalizeForSearch(breadcrumb.join(" ")),
      });
    }
    current = null;
  };

  for (const line of lines) {
    const heading = HEADING_RE.exec(line);
    if (heading) {
      flush();
      const level = heading[1]!.length;
      const title = cleanTitle(heading[2]!);
      while (stack.length > 0 && stack[stack.length - 1]!.level >= level) {
        stack.pop();
      }
      stack.push({ level, title });
      current = { title, breadcrumb: stack.map((item) => item.title), body: [] };
      continue;
    }
    if (current) current.body.push(line);
  }
  flush();

  return sections;
}

/**
 * 查询分词：中文切 2-gram（整段不超过 3 字时保留整段），
 * 英文/数字按词切（长度 >= 2）。
 * maxTokens 只用于限制查询长度；构建 IDF 统计时传 Infinity，避免长文档被截断。
 */
export function tokenize(query: string, maxTokens = MAX_QUERY_TOKENS): string[] {
  const normalized = query.toLowerCase();
  const tokens = new Set<string>();

  for (const match of normalized.matchAll(/[a-z0-9]+/g)) {
    if (match[0].length >= 2) tokens.add(match[0]);
  }
  for (const match of normalized.matchAll(/[\u4e00-\u9fff]+/g)) {
    const run = match[0];
    if (run.length <= 3) tokens.add(run);
    for (let i = 0; i + 2 <= run.length; i++) {
      tokens.add(run.slice(i, i + 2));
    }
  }

  return [...tokens].slice(0, maxTokens);
}

function countHits(haystack: string, needle: string): number {
  if (!needle) return 0;
  let hits = 0;
  let from = 0;
  while (hits < MAX_TERM_HITS) {
    const found = haystack.indexOf(needle, from);
    if (found === -1) break;
    hits += 1;
    from = found + needle.length;
  }
  return hits;
}

/**
 * 统计每个 token 出现在多少个段落中（段落内去重），用于 IDF 加权。
 * 语料不大（数百段落），首次检索时构建一次即可。
 */
export function buildDocumentFrequency(sections: GuideSection[]): Map<string, number> {
  const df = new Map<string, number>();
  for (const section of sections) {
    for (const token of new Set(tokenize(`${section.titlePlain} ${section.plain}`, Infinity))) {
      df.set(token, (df.get(token) ?? 0) + 1);
    }
  }
  return df;
}

/** 出现频率超过该比例的 token 视为虚词（如"什么""怎么"），不参与打分 */
const COMMON_TERM_RATIO = 0.3;

/** 标题命中权重远高于正文命中；整串命中再额外加分 */
function scoreSection(
  section: GuideSection,
  tokens: Array<{ token: string; weight: number }>,
  normalizedQuery: string,
): number {
  let score = 0;

  for (const { token, weight } of tokens) {
    const titleHits = countHits(section.titlePlain, token);
    const bodyHits = countHits(section.plain, token);
    if (titleHits === 0 && bodyHits === 0) continue;
    score += (titleHits * 6 + bodyHits) * weight;
  }

  if (normalizedQuery.length >= 2) {
    if (section.titlePlain.includes(normalizedQuery)) score += 12;
    if (section.plain.includes(normalizedQuery)) score += 8;
  }

  return score;
}

/**
 * 按相关度返回最匹配的段落（得分相同保持文档原始顺序）。
 * 传入 df（buildDocumentFrequency 的结果）后按 IDF 加权，并丢弃过泛的虚词 token。
 */
export function searchSections(
  sections: GuideSection[],
  query: string,
  limit = 4,
  df?: Map<string, number>,
): GuideSection[] {
  const rawTokens = tokenize(query);
  if (rawTokens.length === 0) return [];
  const normalizedQuery = normalizeForSearch(query);

  const tokens = rawTokens
    .map((token) => {
      const freq = df?.get(token) ?? 0;
      return {
        token,
        freq,
        // df 越大权重越低；未出现的 token 按 df=0 处理（最高权重）
        weight: df ? Math.log(1 + sections.length / (1 + freq)) : 1,
      };
    })
    .filter((item) => !df || item.freq / sections.length <= COMMON_TERM_RATIO);

  if (tokens.length === 0) return [];

  return sections
    .map((section) => ({ section, score: scoreSection(section, tokens, normalizedQuery) }))
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.max(1, limit))
    .map((item) => item.section);
}
