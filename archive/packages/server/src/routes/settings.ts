/**
 * 设置路由：读取/更新模型 provider、ZJU 凭据、应用设置。
 * 敏感字段不回传，仅返回脱敏状态。
 */

import type { FastifyPluginAsync } from "fastify";
import {
  ok,
  wrap,
  AppError,
  ErrorCode,
  type ModelProviderConfig,
} from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";
import { createRateLimiter } from "../util/rate-limit.js";

const SETTING_KEY = "model-providers";
const APP_SETTING_KEY = "app-settings";

/** 凭据/模型配置写接口限流 */
const writeLimiter = createRateLimiter({ windowMs: 60_000, max: 20 });

export function settingsRoutes(
  deps: ServicesContainer & { config: ServerConfig },
): FastifyPluginAsync {
  return async (app) => {
    // GET /api/settings — 返回脱敏设置 + 凭据状态
    app.get("/", async () => {
      const providers = deps.settings.get<ModelProviderConfig[]>(
        SETTING_KEY,
      );
      const appSettings = deps.settings.get<Record<string, unknown>>(
        APP_SETTING_KEY,
      );
      // apiKey 只存加密库；这里回填掩码提示（***末4位），供 UI 展示
      const encrypted = await deps.credentials.get<ModelProviderConfig[]>(
        "model-providers",
      );
      const encById = new Map((encrypted ?? []).map((p) => [p.id, p]));
      const maskedProviders = (providers ?? []).map((p) => {
        const enc = encById.get(p.id);
        return enc?.apiKey ? { ...p, apiKey: `***${enc.apiKey.slice(-4)}` } : p;
      });
      const credStatus = await deps.auth.getStatus();
      return ok({
        modelProviders: maskedProviders,
        appSettings: appSettings ?? {},
        credentials: credStatus,
      });
    });

    // PUT /api/settings/model-providers
    app.put<{ Body: ModelProviderConfig | ModelProviderConfig[] }>(
      "/model-providers",
      async (req, reply) => {
        if (!writeLimiter.check(req.ip)) {
          return reply.code(429).send({
            ok: false,
            error: {
              code: ErrorCode.RATE_LIMITED,
              message: "尝试过于频繁，请稍后再试。",
            },
          });
        }
        return wrap(async () => {
          const body = req.body;
          const list = Array.isArray(body) ? body : [body];
          for (const p of list) {
            if (!p.id || !p.baseUrl || !p.model) {
              throw new AppError(
                ErrorCode.MODEL_PROVIDER_INVALID,
                "模型 provider 缺少必要字段（id / baseUrl / model）。",
              );
            }
            validateBaseUrl(p.baseUrl);
          }
          // 保留既有加密凭据中的真实 apiKey：
          // 提交空值或掩码占位（"***xxxx"）时不覆盖旧 key，避免误清空
          const existing =
            (await deps.credentials.get<ModelProviderConfig[]>(
              "model-providers",
            )) ?? [];
          const existingById = new Map(existing.map((p) => [p.id, p]));
          const merged = list.map((p) => {
            const prev = existingById.get(p.id);
            const submitted = p.apiKey ?? "";
            const isMask = /^\*{3}.{1,4}$/.test(submitted);
            const apiKey =
              (!submitted || isMask) && prev?.apiKey ? prev.apiKey : submitted;
            return { ...p, apiKey };
          });
          // 完整配置（含 apiKey）只进加密凭据存储
          await deps.credentials.set("model-providers", merged);
          // 明文 settings 表只存脱敏副本（apiKey 置空），防止密钥二次泄露
          const plain = merged.map((p) => ({ ...p, apiKey: "" }));
          deps.settings.set<ModelProviderConfig[]>(SETTING_KEY, plain);
          return merged.map(maskProvider);
        });
      },
    );

    // PUT /api/settings/zju-credential
    app.put<{ Body: { username: string; password: string } }>(
      "/zju-credential",
      async (req, reply) => {
        if (!writeLimiter.check(req.ip)) {
          return reply.code(429).send({
            ok: false,
            error: {
              code: ErrorCode.RATE_LIMITED,
              message: "尝试过于频繁，请稍后再试。",
            },
          });
        }
        return wrap(async () => {
          const { username, password } = req.body ?? { username: "", password: "" };
          await deps.auth.setCredential({ username, password });
          return { ok: true };
        });
      },
    );

    // PUT /api/settings/app — 非敏感应用设置
    app.put<{ Body: Record<string, unknown> }>("/app", async (req) => {
      return wrap(async () => {
        deps.settings.set(APP_SETTING_KEY, req.body);
        return { ok: true };
      });
    });
  };
}

function maskProvider(p: ModelProviderConfig): ModelProviderConfig {
  return {
    ...p,
    apiKey: p.apiKey ? `***${p.apiKey.slice(-4)}` : "",
  };
}

/** baseUrl 安全校验：仅 https（本机回环可用 http），禁止内嵌凭据 → 防 SSRF */
function validateBaseUrl(baseUrl: string): void {
  let u: URL;
  try {
    u = new URL(baseUrl);
  } catch {
    throw new AppError(
      ErrorCode.MODEL_PROVIDER_INVALID,
      "baseUrl 不是合法的 URL。",
    );
  }
  const isLoopback = ["localhost", "127.0.0.1", "[::1]", "::1"].includes(
    u.hostname,
  );
  if (u.protocol !== "https:" && !(u.protocol === "http:" && isLoopback)) {
    throw new AppError(
      ErrorCode.MODEL_PROVIDER_INVALID,
      "baseUrl 仅允许 https://（本机回环地址可用 http://）。",
    );
  }
  if (u.username || u.password) {
    throw new AppError(
      ErrorCode.MODEL_PROVIDER_INVALID,
      "baseUrl 不允许携带用户名/密码。",
    );
  }
}
