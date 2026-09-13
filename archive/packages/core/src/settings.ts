import { z } from "zod";

/** 模型 provider 协议 */
export type ModelProtocol = "openai" | "anthropic";

export const modelProviderConfigSchema = z.object({
  id: z.string(),
  name: z.string(),
  protocol: z.enum(["openai", "anthropic"]),
  baseUrl: z.string().url(),
  apiKey: z.string(),
  model: z.string(),
  enabled: z.boolean().default(true),
});

export type ModelProviderConfig = z.infer<typeof modelProviderConfigSchema>;

/** 应用层设置（敏感字段如 apiKey / password 不在此结构内，由凭据存储单独管理） */
export type AppSettings = {
  /** 默认使用的模型 provider id */
  defaultModelProviderId: string | null;
  /** 下载目录 */
  downloadDir: string;
  /** 单文件下载是否需要确认 */
  confirmSingleDownload: boolean;
  /** 默认课程提醒提前分钟数 */
  courseReminderLeadMinutes: number;
  /** 应用本地访问 token（后端启动时生成，前端调用 API 时带上） */
  accessToken: string | null;
  /** 个性化：昵称（主页问候语 + AI 称呼用户用） */
  nickname?: string;
  /** 个性化：头像（data URL，前端压缩到 256px 后存本地） */
  avatarDataUrl?: string;
  /** 个性化：默认提示词（注入所有 AI 对话，让回答更贴合用户） */
  personaPrompt?: string;
};

export const appSettingsSchema = z.object({
  defaultModelProviderId: z.string().nullable(),
  downloadDir: z.string(),
  confirmSingleDownload: z.boolean().default(false),
  courseReminderLeadMinutes: z.number().int().default(15),
  accessToken: z.string().nullable(),
  nickname: z.string().max(24).optional(),
  avatarDataUrl: z.string().max(400_000).optional(),
  personaPrompt: z.string().max(2000).optional(),
});
