import { describe, expect, it } from "vitest";
import { buildSystemPrompt, filterToolsForMode } from "./prompt.js";

const BASE = {
  datetime: "2026-09-08 19:30 (周一)",
  period: "当前为2026-2027-1学期",
};

describe("buildSystemPrompt", () => {
  it("注入当前时间与学期，不残留占位符", () => {
    const prompt = buildSystemPrompt(BASE);
    expect(prompt).toContain("2026-09-08 19:30 (周一)");
    expect(prompt).toContain("当前为2026-2027-1学期");
    expect(prompt).not.toContain("__DATETIME__");
    expect(prompt).not.toContain("__PERIOD__");
  });

  it("设置昵称后要求 AI 用昵称称呼用户", () => {
    const prompt = buildSystemPrompt({ ...BASE, profile: { nickname: "小林" } });
    expect(prompt).toContain("关于用户");
    expect(prompt).toContain("请称呼用户为「小林」");
  });

  it("人设提示词被注入；空白值不产生空段", () => {
    const withPersona = buildSystemPrompt({
      ...BASE,
      profile: { persona: "计算机学院大二学生，喜欢操作系统" },
    });
    expect(withPersona).toContain("计算机学院大二学生，喜欢操作系统");

    const blank = buildSystemPrompt({ ...BASE, profile: { nickname: "  ", persona: "" } });
    expect(blank).not.toContain("关于用户");
  });

  it("brief 模式追加极简回答约束，普通模式没有", () => {
    const brief = buildSystemPrompt({ ...BASE, brief: true });
    expect(brief).toContain("桌面挂件");
    expect(brief).toContain("60 字以内");
    expect(buildSystemPrompt(BASE)).not.toContain("60 字以内");
  });

  it("提供知识库大纲时注入检索规则与目录，且不残留占位符", () => {
    const prompt = buildSystemPrompt({
      ...BASE,
      guideOutline: "- 选课：选课规则、选课技巧",
    });
    expect(prompt).toContain("关于浙大校园常识（知识库）");
    expect(prompt).toContain("zju_search_guide");
    expect(prompt).toContain("参考《浙江大学本科新生指引》");
    expect(prompt).toContain("- 选课：选课规则、选课技巧");
    expect(prompt).not.toContain("__GUIDE_OUTLINE__");
  });

  it("知识库不可用（大纲为空）时整段省略", () => {
    expect(buildSystemPrompt(BASE)).not.toContain("关于浙大校园常识");
    expect(buildSystemPrompt({ ...BASE, guideOutline: "  " })).not.toContain(
      "关于浙大校园常识",
    );
  });
});

describe("filterToolsForMode", () => {
  const tools = [
    { name: "read_tool", riskLevel: "read", requiresConfirmation: false },
    { name: "read_confirm_tool", riskLevel: "read", requiresConfirmation: true },
    { name: "download_tool", riskLevel: "external_download", requiresConfirmation: true },
    { name: "write_tool", riskLevel: "write", requiresConfirmation: true },
  ];

  it("非只读模式返回全部工具", () => {
    expect(filterToolsForMode(tools, false)).toHaveLength(4);
  });

  it("只读模式只保留 read 且无需确认的工具", () => {
    const filtered = filterToolsForMode(tools, true);
    expect(filtered.map((tool) => tool.name)).toEqual(["read_tool"]);
  });
});
