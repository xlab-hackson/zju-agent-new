import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import {
  buildDocumentFrequency,
  cleanTitle,
  extractDocTitle,
  normalizeForSearch,
  searchSections,
  splitIntoSections,
  tokenize,
} from "./search.js";
import {
  getGuideOutline,
  loadGuideIndex,
  readGuideDoc,
  resetGuideCache,
  searchGuide,
} from "./index.js";

const KNOWLEDGE_DIR = fileURLToPath(new URL("../../knowledge", import.meta.url));

describe("splitIntoSections", () => {
  it("按标题层级切段并保留标题链", () => {
    const md = [
      "# 选课规则",
      "",
      "选课分为预选和正选两个阶段，采用随机抽取方式。",
      "",
      "## 抽签机制",
      "",
      "系统会在预选结束后统一抽取，与网速无关。",
      "",
      "### 志愿优先级",
      "",
      "第一志愿优先于第二志愿。",
    ].join("\n");

    const sections = splitIntoSections("course_sys/rules.md", "选课", md);

    expect(sections).toHaveLength(3);
    expect(sections[0]).toMatchObject({
      doc: "course_sys/rules.md",
      chapter: "选课",
      title: "选课规则",
      breadcrumb: ["选课规则"],
    });
    expect(sections[1]).toMatchObject({
      title: "抽签机制",
      breadcrumb: ["选课规则", "抽签机制"],
    });
    expect(sections[1]!.text).toContain("统一抽取");
    expect(sections[2]!.breadcrumb).toEqual(["选课规则", "抽签机制", "志愿优先级"]);
  });

  it("丢弃只有标题、没有正文的段落", () => {
    const md = "# 标题\n\n## 空段落\n\n## 有内容\n\n这里是一段足够长的正文内容。";
    const sections = splitIntoSections("a.md", "其他", md);
    expect(sections.map((section) => section.title)).toEqual(["有内容"]);
  });

  it("清洗标题里的链接语法", () => {
    expect(cleanTitle("[学部院系](https://www.zju.edu.cn/)")).toBe("学部院系");
  });

  it("单独抽取文档 H1 作为标题", () => {
    expect(extractDocTitle("## 小节\n\n正文")).toBe("小节");
    expect(extractDocTitle("# 选课规则\n\n## 小节\n\n正文")).toBe("选课规则");
    expect(extractDocTitle("\uFEFF# 校园区域\n\n正文")).toBe("校园区域");
    expect(extractDocTitle("没有标题的正文")).toBe("");
  });

  it("带 BOM 的文件首个标题仍能识别", () => {
    const sections = splitIntoSections(
      "a.md",
      "生活",
      "\uFEFF# 校园区域\n\n正文内容足够长，可以保留下来。",
    );
    expect(sections[0]).toMatchObject({ title: "校园区域", breadcrumb: ["校园区域"] });
  });
});

describe("tokenize", () => {
  it("中文切 2-gram，短词保留整段", () => {
    const tokens = tokenize("绩点怎么算");
    expect(tokens).toContain("绩点");
    expect(tokens).toContain("怎么");
    expect(tokens).toContain("么算");
  });

  it("英文数字按词切分并忽略单字符", () => {
    expect(tokenize("GPA 2026")).toEqual(["gpa", "2026"]);
    expect(tokenize("a")).toEqual([]);
  });
});

describe("searchSections", () => {
  const sections = [
    ...splitIntoSections("body.md", "学习", "# 杂项\n\n这里只是顺带提到了绩点，不是重点。"),
    ...splitIntoSections("title.md", "学习", "# 绩点\n\n这是标题命中的段落，应当排在第一。"),
  ];

  it("标题命中优先于正文命中", () => {
    const hits = searchSections(sections, "绩点", 2);
    expect(hits.map((hit) => hit.doc)).toEqual(["title.md", "body.md"]);
  });

  it("无关查询返回空", () => {
    expect(searchSections(sections, "食堂")).toEqual([]);
  });
});

describe("buildDocumentFrequency", () => {
  it("统计 token 出现在多少个段落中（段内去重）", () => {
    const sections = [
      ...splitIntoSections("a.md", "学习", "# 食堂\n\n食堂什么都有，而且食堂很便宜。"),
      ...splitIntoSections("b.md", "学习", "# 图书馆\n\n图书馆什么都有，而且图书馆很安静。"),
    ];
    const df = buildDocumentFrequency(sections);
    expect(df.get("什么")).toBe(2);
    expect(df.get("食堂")).toBe(1);
    expect(df.get("图书馆")).toBe(1);
  });
});

describe("normalizeForSearch", () => {
  it("去掉 markdown 装饰并统一小写", () => {
    expect(normalizeForSearch("## **绩点** [说明](http://x)")).toBe("绩点 说明");
  });
});

describe("知识库真实数据", () => {
  beforeEach(() => {
    process.env.ZJU_AGENT_KNOWLEDGE_DIR = KNOWLEDGE_DIR;
    resetGuideCache();
  });

  afterAll(() => {
    delete process.env.ZJU_AGENT_KNOWLEDGE_DIR;
    resetGuideCache();
  });

  it("加载指引文档并生成章节大纲", () => {
    const index = loadGuideIndex();
    expect(index).not.toBeNull();
    expect(index!.docs.size).toBeGreaterThan(50);

    const outline = getGuideOutline();
    expect(outline).toContain("选课");
    expect(outline).toContain("奖助");
  });

  it("能检索到浙大特有制度内容", () => {
    const hits = searchGuide("绩点怎么算", 3);
    expect(hits.length).toBeGreaterThan(0);
    expect(hits[0]!.doc).toMatch(/\.md$/);
    expect(hits[0]!.text.length).toBeGreaterThan(0);
  });

  it("能按路径读取文档全文", () => {
    const doc = readGuideDoc("course_sys/rules.md");
    expect(doc.title).toBe("选课规则");
    expect(doc.text).toContain("#");
    expect(doc.truncated).toBe(false);
  });

  it("带 BOM 的文档标题取自 H1 而非首个正文小节", () => {
    expect(readGuideDoc("life/campus.md").title).toBe("校园区域");
  });

  it("读取不存在的文档给出可用路径提示", () => {
    expect(() => readGuideDoc("nope.md")).toThrowError(/不存在/);
  });
});
