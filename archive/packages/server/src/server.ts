/**
 * Fastify 应用装配。
 */

import Fastify from "fastify";
import cors from "@fastify/cors";
import { ok, setUnknownErrorSink } from "@zju-agent/core";
import type { ServerConfig } from "./config/env.js";
import { logger } from "./config/logger.js";
import { createAuthMiddleware } from "./middleware/auth.js";
import { healthRoutes } from "./routes/health.js";
import { bootstrapRoutes } from "./routes/bootstrap.js";
import { settingsRoutes } from "./routes/settings.js";
import { authRoutes } from "./routes/auth.js";
import { zjuCoursesRoutes } from "./routes/zju-courses.js";
import { zdbkRoutes } from "./routes/zdbk.js";
import { noticesRoutes } from "./routes/notices.js";
import { filesRoutes } from "./routes/files.js";
import { agentRoutes } from "./routes/agent.js";
import type { ServicesContainer } from "./services.js";

export type ServerDeps = ServicesContainer & {
  config: ServerConfig;
};

/** 仅允许本机来源（localhost/127.0.0.1），阻断任意网页跨源访问本地 API */
function isLocalOrigin(origin: string): boolean {
  try {
    const u = new URL(origin);
    return (
      (u.protocol === "http:" || u.protocol === "https:") &&
      ["localhost", "127.0.0.1", "[::1]", "::1"].includes(u.hostname)
    );
  } catch {
    return false;
  }
}

/** 业务错误码 → HTTP 状态码映射（默认保持 200，未知错误 500） */
function errorStatus(code: string | undefined): number | undefined {
  switch (code) {
    case "UNKNOWN_ERROR":
      return 500;
    case "TOOL_INPUT_INVALID":
      return 400;
    case "FILE_NOT_FOUND":
      return 404;
    case "TOOL_CONFIRMATION_EXPIRED":
      return 404;
    case "MODEL_AUTH_FAILED":
      return 502;
    case "ZJU_RESPONSE_PARSE_FAILED":
      return 502;
    case "ZJU_CREDENTIAL_MISSING":
      return 400;
    case "MODEL_PROVIDER_INVALID":
      return 400;
    default:
      return undefined;
  }
}

export async function createServer(deps: ServerDeps) {
  const app = Fastify({
    logger: false,
    bodyLimit: 50 * 1024 * 1024,
  });

  // CORS：仅反射本机来源。任意公网网页将无法跨源读取本地 API。
  await app.register(cors, {
    origin: (origin, cb) => {
      // 非本机来源：不返回 CORS 头（浏览器侧阻断），而非抛错 500
      cb(null, !origin || isLocalOrigin(origin));
    },
    credentials: true,
  });

  // 鉴权钩子
  app.addHook("onRequest", createAuthMiddleware(deps.config));

  // wrap() 捕获的非 AppError：原始信息只进日志，不下发客户端
  setUnknownErrorSink((err) => {
    logger.warn("未捕获异常", {
      message: err instanceof Error ? err.message : String(err),
      stack: err instanceof Error ? err.stack : undefined,
    });
  });

  // 业务信封错误 → 设置合适的 HTTP 状态码。
  // 在序列化前检查已解析的响应对象（Fastify 自身错误仍走 setErrorHandler）
  app.addHook("preSerialization", async (_request, reply, payload) => {
    if (
      payload !== null &&
      typeof payload === "object" &&
      (payload as { ok?: unknown }).ok === false
    ) {
      const code = (payload as { error?: { code?: string } }).error?.code;
      const status = errorStatus(code);
      if (status && reply.statusCode === 200) {
        reply.code(status);
      }
    }
    return payload;
  });

  // 统一错误处理：只输出泛化信息，原始错误进日志
  app.setErrorHandler((err, _req, reply) => {
    const status = (err as { statusCode?: number }).statusCode ?? 500;
    const code =
      status === 401
        ? "UNAUTHORIZED"
        : status === 400
          ? "TOOL_INPUT_INVALID"
          : "UNKNOWN_ERROR";
    const message =
      status === 400
        ? "请求格式错误。"
        : status === 413
          ? "请求体过大。"
          : "服务器内部错误。";
    logger.warn("Fastify 请求处理错误", {
      status,
      message: err instanceof Error ? err.message : String(err),
    });
    reply.code(status).send({
      ok: false,
      error: {
        code,
        message,
        retryable: false,
      },
    });
  });

  await app.register(healthRoutes, { prefix: "/api" });
  await app.register(bootstrapRoutes(deps), { prefix: "/api" });
  await app.register(settingsRoutes(deps), { prefix: "/api/settings" });
  await app.register(authRoutes(deps), { prefix: "/api/auth" });
  await app.register(zjuCoursesRoutes(deps), { prefix: "/api/zju" });
  await app.register(zdbkRoutes(deps), { prefix: "/api/zju" });
  await app.register(noticesRoutes(deps), { prefix: "/api/zju" });
  await app.register(filesRoutes(deps), { prefix: "/api/files" });
  await app.register(agentRoutes(deps), { prefix: "/api/agent" });

  // 简单根路由
  app.get("/", async () => ok({ name: "zju-campus-agent-server", ok: true }));

  return app;
}