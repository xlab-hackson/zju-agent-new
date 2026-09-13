/**
 * Agent 对话 hooks。
 * - useConversations: 会话列表
 * - useConversation: 单会话 + 消息历史
 * - useSendMessage: 发起对话（SSE 流式）
 * - useConfirmTool: 确认/拒绝高风险工具
 * - useDeleteConversation
 *
 * SSE 用 fetch + ReadableStream 读取，每条 `data: <json>\n\n` 解析为 AgentStreamEvent。
 */

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { ApiResponse } from "@zju-agent/core";
import { useApiFetch } from "./bootstrap.js";

export type ChatMessage = {
  id: string;
  conversationId: string;
  role: "system" | "user" | "assistant" | "tool";
  content: string;
  metadata?: {
    toolCalls?: Array<{ id: string; name: string; input: unknown }>;
    toolCallId?: string;
    name?: string;
  };
  createdAt: string;
};

export type ConversationSummary = {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
};

export type ConversationDetail = ConversationSummary & {
  messages: ChatMessage[];
};

export function useConversations() {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["agent", "conversations"],
    queryFn: async () => {
      const res = await apiFetch("/api/agent/conversations");
      const json = (await res.json()) as ApiResponse<ConversationSummary[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
  });
}

export function useConversation(id: string | null) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["agent", "conversation", id],
    enabled: !!id,
    queryFn: async () => {
      const res = await apiFetch(`/api/agent/conversations/${id}`);
      const json = (await res.json()) as ApiResponse<ConversationDetail>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
  });
}

export type AgentEvent =
  | { type: "text"; delta: string }
  | { type: "tool_call_start"; toolCall: { id: string; name: string; input: unknown } }
  | { type: "tool_call_end"; toolCall: { id: string; name: string; input: unknown } }
  | { type: "tool_result"; toolCallId: string; result: unknown; ok: boolean }
  | {
      type: "confirmation_required";
      confirmationId: string;
      toolName: string;
      summary: string;
      inputPreview: unknown;
    }
  | { type: "message_end"; finishReason: string }
  | { type: "error"; code: string; message: string }
  | { type: "done"; paused: boolean; confirmationId: string | null; conversationId: string };

/** 发送消息：返回 SSE 事件流（AsyncIterable） */
export function useSendMessage() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      conversationId?: string;
      message: string;
      onEvent: (event: AgentEvent) => void;
    }) => {
      const res = await apiFetch("/api/agent/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify({
          conversationId: input.conversationId,
          message: input.message,
        }),
      });
      if (!res.ok || !res.body) {
        const text = await res.text().catch(() => "");
        throw new Error(text || `请求失败 (HTTP ${res.status})`);
      }
      return consumeSSE(res.body, input.onEvent);
    },
    onSuccess: (_data, variables) => {
      void qc.invalidateQueries({ queryKey: ["agent", "conversations"] });
      if (variables.conversationId) {
        void qc.invalidateQueries({
          queryKey: ["agent", "conversation", variables.conversationId],
        });
      }
    },
  });
}

/**
 * 桌面挂件的一次性问答：`mode: "widget"` 表示
 * 不建会话、不落库、只用只读工具、服务端强制简短回答。
 */
export function useQuickAsk() {
  const apiFetch = useApiFetch();
  return useMutation({
    mutationFn: async (input: {
      message: string;
      onEvent: (event: AgentEvent) => void;
    }) => {
      const res = await apiFetch("/api/agent/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify({ message: input.message, mode: "widget" }),
      });
      if (!res.ok || !res.body) {
        const text = await res.text().catch(() => "");
        throw new Error(text || `请求失败 (HTTP ${res.status})`);
      }
      return consumeSSE(res.body, input.onEvent);
    },
  });
}

/** 确认/拒绝工具：同样走 SSE */export function useConfirmTool() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: {
      confirmationId: string;
      decision: "approve" | "reject";
      onEvent: (event: AgentEvent) => void;
    }) => {
      const res = await apiFetch("/api/agent/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
        body: JSON.stringify(input),
      });
      if (!res.ok || !res.body) {
        const text = await res.text().catch(() => "");
        throw new Error(text || `请求失败 (HTTP ${res.status})`);
      }
      return consumeSSE(res.body, input.onEvent);
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["agent", "conversations"] });
    },
  });
}

export function useDeleteConversation() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (id: string) => {
      const res = await apiFetch(`/api/agent/conversations/${id}`, {
        method: "DELETE",
      });
      const json = (await res.json()) as ApiResponse<{ ok: boolean }>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["agent", "conversations"] });
    },
  });
}

/** 读取 SSE 流，逐事件回调 */
async function consumeSSE(
  body: ReadableStream<Uint8Array>,
  onEvent: (e: AgentEvent) => void,
): Promise<void> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split("\n\n");
    buffer = parts.pop() ?? "";
    for (const part of parts) {
      const line = part.trim();
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (!data) continue;
      try {
        onEvent(JSON.parse(data) as AgentEvent);
      } catch {
        // 忽略解析错误
      }
    }
  }
}
