import { describe, expect, it } from "vitest";
import { joinUrl } from "./openai.js";

describe("joinUrl", () => {
  it("裸域名自动补 /v1", () => {
    expect(joinUrl("https://api.openai.com", "/chat/completions")).toBe(
      "https://api.openai.com/v1/chat/completions",
    );
    expect(joinUrl("https://api.deepseek.com/", "/chat/completions")).toBe(
      "https://api.deepseek.com/v1/chat/completions",
    );
  });

  it("baseUrl 已带 /v1 时不重复补", () => {
    expect(joinUrl("https://api.openai.com/v1", "/chat/completions")).toBe(
      "https://api.openai.com/v1/chat/completions",
    );
    expect(joinUrl("https://api.openai.com/v1/", "/chat/completions")).toBe(
      "https://api.openai.com/v1/chat/completions",
    );
  });

  it("其他版本段（如智谱 /v4）不再补 /v1", () => {
    expect(joinUrl("https://open.bigmodel.cn/api/paas/v4", "/chat/completions")).toBe(
      "https://open.bigmodel.cn/api/paas/v4/chat/completions",
    );
    expect(joinUrl("https://host/api/v2", "/chat/completions")).toBe(
      "https://host/api/v2/chat/completions",
    );
  });

  it("版本段出现在路径中间时直接拼接", () => {
    expect(joinUrl("https://host/v1/proxy", "/chat/completions")).toBe(
      "https://host/v1/proxy/chat/completions",
    );
  });
});
