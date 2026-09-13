/**
 * OpenAI Chat Completions 适配器。
 * 兼容 /v1/chat/completions，支持 tools / tool_choice / streaming。
 */

import type { AgentMessage, AgentStreamEvent, ToolManifest } from "@zju-agent/core";
import type { LlmProvider, LlmRequest, FetchLike } from "../types.js";

export class OpenAIProvider implements LlmProvider {
  constructor(private fetchImpl: FetchLike = fetch) {}

  async *stream(req: LlmRequest): AsyncIterable<AgentStreamEvent> {
    const body = this.toRequestBody(req);
    const url = joinUrl(req.baseUrl, "/chat/completions");
    const res = await this.fetchImpl(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${req.apiKey}`,
      },
      body: JSON.stringify({ ...body, stream: true }),
    });
    if (!res.ok || !res.body) {
      const text = await res.text().catch(() => "");
      yield {
        type: "error",
        code: "MODEL_AUTH_FAILED",
        message: `模型请求失败 (HTTP ${res.status}): ${text.slice(0, 200)}`,
      };
      return;
    }

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    const toolCalls: Map<number, { id: string; name: string; argBuf: string }> =
      new Map();
    const started = new Set<number>();
    let finishReason = "stop";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed.startsWith("data:")) continue;
        const data = trimmed.slice(5).trim();
        if (data === "[DONE]") continue;
        try {
          const json = JSON.parse(data) as {
            choices?: Array<{
              delta?: {
                content?: string;
                tool_calls?: Array<{
                  index: number;
                  id?: string;
                  function?: { name?: string; arguments?: string };
                }>;
              };
              finish_reason?: string;
            }>;
          };
          const choice = json.choices?.[0];
          if (!choice) continue;
          if (choice.finish_reason) finishReason = choice.finish_reason;
          const delta = choice.delta;
          if (delta?.content) {
            yield { type: "text", delta: delta.content };
          }
          if (delta?.tool_calls) {
            for (const tc of delta.tool_calls) {
              const existing = toolCalls.get(tc.index);
              // 首次出现该工具调用时，先发 tool_call_start（与 Anthropic 行为对齐，
              // 前端依赖它渲染工具步骤）
              if (!existing && !started.has(tc.index)) {
                started.add(tc.index);
                yield {
                  type: "tool_call_start",
                  toolCall: {
                    id: tc.id ?? `call_${tc.index}`,
                    name: tc.function?.name ?? "",
                    input: {},
                  },
                };
              }
              const id = tc.id ?? existing?.id ?? `call_${tc.index}`;
              const name = tc.function?.name ?? existing?.name ?? "";
              const arg = (existing?.argBuf ?? "") + (tc.function?.arguments ?? "");
              toolCalls.set(tc.index, { id, name, argBuf: arg });
            }
          }
        } catch {
          // 忽略解析错误
        }
      }
    }

    // 流结束后输出 tool_call 事件
    for (const [, tc] of toolCalls) {
      let input: unknown = tc.argBuf;
      try {
        input = tc.argBuf ? JSON.parse(tc.argBuf) : {};
      } catch {
        input = { _raw: tc.argBuf };
      }
      const toolCall = { id: tc.id, name: tc.name, input };
      yield { type: "tool_call_end", toolCall };
    }

    yield { type: "message_end", finishReason };
  }

  private toRequestBody(req: LlmRequest): Record<string, unknown> {
    const messages: unknown[] = [];
    if (req.system) {
      messages.push({ role: "system", content: req.system });
    }
    for (const m of req.messages) {
      messages.push(toOpenAIMessage(m));
    }
    const body: Record<string, unknown> = {
      model: req.model,
      messages,
      stream: true,
      // 防止异常生成导致成本失控（与 Anthropic 适配器对齐）
      max_tokens: 4096,
    };
    if (req.tools.length > 0) {
      body["tools"] = req.tools.map((t) => toOpenAITool(t));
      body["tool_choice"] = req.toolChoice ?? "auto";
    }
    return body;
  }
}

export function joinUrl(base: string, path: string): string {
  const b = base.replace(/\/+$/, "");
  // baseUrl 已含版本段（/v1 OpenAI、/v4 智谱等）时直接拼接，否则补 /v1
  return /\/v\d+(\/|$)/.test(b) ? b + path : b + "/v1" + path;
}

function toOpenAIMessage(m: AgentMessage): Record<string, unknown> {
  switch (m.role) {
    case "system":
      return { role: "system", content: m.content };
    case "user":
      return { role: "user", content: m.content };
    case "assistant": {
      if (m.toolCalls && m.toolCalls.length > 0) {
        return {
          role: "assistant",
          content: m.content || null,
          tool_calls: m.toolCalls.map((tc) => ({
            id: tc.id,
            type: "function",
            function: {
              name: tc.name,
              arguments: JSON.stringify(tc.input),
            },
          })),
        };
      }
      return { role: "assistant", content: m.content };
    }
    case "tool":
      return {
        role: "tool",
        tool_call_id: m.toolCallId,
        content: m.content,
      };
  }
}

function toOpenAITool(t: ToolManifest): Record<string, unknown> {
  return {
    type: "function",
    function: {
      name: t.name,
      description: t.description,
      parameters: t.inputSchema,
    },
  };
}
