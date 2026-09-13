/**
 * Agent 内部统一消息类型。
 * 用于在 OpenAI / Anthropic 协议间转换。
 */
export type ToolCall = {
  id: string;
  name: string;
  input: unknown;
};

export type AgentMessage =
  | { role: "system"; content: string }
  | { role: "user"; content: string }
  | { role: "assistant"; content: string; toolCalls?: ToolCall[] }
  | { role: "tool"; toolCallId: string; name: string; content: string };

/** 流式事件 */
export type AgentStreamEvent =
  | { type: "text"; delta: string }
  | { type: "tool_call_start"; toolCall: ToolCall }
  | { type: "tool_call_end"; toolCall: ToolCall }
  | { type: "tool_result"; toolCallId: string; result: unknown; ok: boolean }
  | {
      type: "confirmation_required";
      confirmationId: string;
      toolName: string;
      summary: string;
      inputPreview: unknown;
    }
  | { type: "message_end"; finishReason: string }
  | { type: "error"; code: string; message: string };

export type Conversation = {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
};
