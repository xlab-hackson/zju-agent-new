/**
 * Anthropic Messages 适配器。
 * 兼容 /v1/messages，支持 tools / streaming。
 */

import type { AgentMessage, AgentStreamEvent, ToolManifest } from "@zju-agent/core";
import type { LlmProvider, LlmRequest, FetchLike } from "../types.js";

export class AnthropicProvider implements LlmProvider {
  constructor(private fetchImpl: FetchLike = fetch) {}

  async *stream(req: LlmRequest): AsyncIterable<AgentStreamEvent> {
    const body = this.toRequestBody(req);
    const url = joinUrl(req.baseUrl, "/messages");
    const res = await this.fetchImpl(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": req.apiKey,
        "anthropic-version": "2023-06-01",
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
        if (!data) continue;
        try {
          const evt = JSON.parse(data) as {
            type: string;
            index?: number;
            content_block?: {
              type?: string;
              id?: string;
              name?: string;
              text?: string;
            };
            delta?: {
              type?: string;
              text?: string;
              partial_json?: string;
              stop_reason?: string;
            };
            message?: { stop_reason?: string };
          };
          if (evt.type === "content_block_start") {
            const block = evt.content_block;
            if (block?.type === "tool_use" && evt.index != null) {
              toolCalls.set(evt.index, {
                id: block.id ?? `call_${evt.index}`,
                name: block.name ?? "",
                argBuf: "",
              });
              yield {
                type: "tool_call_start",
                toolCall: {
                  id: block.id ?? `call_${evt.index}`,
                  name: block.name ?? "",
                  input: {},
                },
              };
            }
          } else if (evt.type === "content_block_delta") {
            const delta = evt.delta;
            if (delta?.type === "text_delta" && delta.text) {
              yield { type: "text", delta: delta.text };
            } else if (delta?.type === "input_json_delta" && evt.index != null) {
              const tc = toolCalls.get(evt.index);
              if (tc) {
                tc.argBuf += delta.partial_json ?? "";
              }
            }
          } else if (evt.type === "message_stop") {
            finishReason = "stop";
          } else if (evt.type === "message_delta") {
            if (evt.delta?.stop_reason) {
              finishReason = evt.delta.stop_reason;
            }
          }
        } catch {
          // 忽略
        }
      }
    }

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
    const systemParts: string[] = [];
    if (req.system) systemParts.push(req.system);
    for (const m of req.messages) {
      const out = toAnthropicMessage(m);
      if (out.role === "system") {
        systemParts.push(out.content as string);
      } else {
        messages.push(out);
      }
    }
    const body: Record<string, unknown> = {
      model: req.model,
      max_tokens: 4096,
      messages,
      stream: true,
    };
    if (systemParts.length > 0) {
      body["system"] = systemParts.join("\n\n");
    }
    if (req.tools.length > 0) {
      body["tools"] = req.tools.map((t) => toAnthropicTool(t));
    }
    return body;
  }
}

function joinUrl(base: string, path: string): string {
  const b = base.replace(/\/+$/, "");
  if (b.endsWith("/v1")) return b + path;
  return b + "/v1" + path;
}

function toAnthropicMessage(m: AgentMessage): Record<string, unknown> {
  switch (m.role) {
    case "system":
      return { role: "system", content: m.content };
    case "user":
      return { role: "user", content: m.content };
    case "assistant": {
      const content: unknown[] = [];
      if (m.content) content.push({ type: "text", text: m.content });
      if (m.toolCalls) {
        for (const tc of m.toolCalls) {
          content.push({
            type: "tool_use",
            id: tc.id,
            name: tc.name,
            input: tc.input,
          });
        }
      }
      return { role: "assistant", content };
    }
    case "tool":
      return {
        role: "user",
        content: [
          {
            type: "tool_result",
            tool_use_id: m.toolCallId,
            content: m.content,
          },
        ],
      };
  }
}

function toAnthropicTool(t: ToolManifest): Record<string, unknown> {
  return {
    name: t.name,
    description: t.description,
    input_schema: t.inputSchema,
  };
}
