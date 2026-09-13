import { z } from "zod";

/** 工具风险等级 */
export type ToolRiskLevel =
  | "read"
  | "write"
  | "payment"
  | "external_download";

export const toolRiskLevelSchema = z.enum([
  "read",
  "write",
  "payment",
  "external_download",
]);

/** 工具执行上下文 */
export type ToolContext = {
  userId: "local";
  conversationId: string;
  requestId: string;
};

/** 工具结果 */
export type ToolResult = {
  ok: boolean;
  data?: unknown;
  error?: {
    code: string;
    message: string;
    detail?: unknown;
  };
};

/** 工具定义。execute 在后端调用，前端不直接执行。 */
export type AgentTool = {
  name: string;
  description: string;
  /** JSON Schema（OpenAI/Anthropic 兼容） */
  inputSchema: Record<string, unknown>;
  riskLevel: ToolRiskLevel;
  requiresConfirmation: boolean;
  execute(input: unknown, context: ToolContext): Promise<ToolResult>;
};

/** 供序列化给 LLM 的工具元数据（剥离 execute） */
export type ToolManifest = {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  riskLevel: ToolRiskLevel;
  requiresConfirmation: boolean;
};

export function toManifest(tool: AgentTool): ToolManifest {
  return {
    name: tool.name,
    description: tool.description,
    inputSchema: tool.inputSchema,
    riskLevel: tool.riskLevel,
    requiresConfirmation: tool.requiresConfirmation,
  };
}

/** 待确认的高风险调用 */
export type PendingConfirmation = {
  id: string;
  conversationId: string;
  toolName: string;
  riskLevel: ToolRiskLevel;
  summary: string;
  inputPreview: unknown;
  input: unknown;
  expiresAt: string;
};

export const pendingConfirmationSchema = z.object({
  id: z.string(),
  conversationId: z.string(),
  toolName: z.string(),
  riskLevel: toolRiskLevelSchema,
  summary: z.string(),
  inputPreview: z.unknown(),
  input: z.unknown(),
  expiresAt: z.string(),
});
