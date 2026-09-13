import type { AgentMessage, AgentStreamEvent, ToolManifest } from "@zju-agent/core";

/** Provider 调用配置 */
export type LlmRequest = {
  protocol: "openai" | "anthropic";
  baseUrl: string;
  apiKey: string;
  model: string;
  messages: AgentMessage[];
  tools: ToolManifest[];
  /** 是否强制调用工具 */
  toolChoice?: "auto" | "required" | "none";
  /** 系统提示词（协议层处理） */
  system?: string;
};

/** Provider 接口：流式输出统一事件 */
export interface LlmProvider {
  stream(req: LlmRequest): AsyncIterable<AgentStreamEvent>;
}

/** 注入的 fetch（Node 18+ 原生支持，Electron/Capacitor 也可注入） */
export type FetchLike = typeof fetch;
