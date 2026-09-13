/**
 * @zju-agent/llm — 大模型适配层
 *
 * - 保存统一 message 类型
 * - 将统一 message 转换为 OpenAI 请求
 * - 将统一 message 转换为 Anthropic 请求
 * - 解析 OpenAI tool calls
 * - 解析 Anthropic tool use
 * - 统一流式输出事件
 * - 隐藏不同 provider 的协议差异
 *
 * 平台无关：不依赖 Node-only API（fetch 由调用方注入）。
 */

export * from "./types.js";
export * from "./provider.js";
export * from "./adapters/openai.js";
export * from "./adapters/anthropic.js";
export * from "./agent-loop.js";
