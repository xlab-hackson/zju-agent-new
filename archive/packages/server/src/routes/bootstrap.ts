/**
 * Bootstrap 路由：前端首次启动时获取连接状态与（开发期）访问 token。
 *
 * 安全考量：
 * - 生产模式下不返回 token，前端通过文件读取或 Electron 注入获取。
 * - 开发期为方便联调，回退 token 经此接口暴露，仅限 127.0.0.1。
 */

import type { FastifyPluginAsync, FastifyRequest } from "fastify";
import { ok } from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";

/** 跨源防护：携带非本机 Origin 的请求拒绝返回 token（纵深防御，CORS 之外的兜底） */
function isTrustedOrigin(origin: string): boolean {
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

export function bootstrapRoutes(
  deps: ServicesContainer & { config: ServerConfig },
): FastifyPluginAsync {
  return async (app) => {
    app.get("/bootstrap", async (req: FastifyRequest, reply) => {
      const origin = req.headers.origin;
      if (origin && !isTrustedOrigin(origin)) {
        return reply.code(403).send({
          ok: false,
          error: { code: "UNAUTHORIZED", message: "拒绝跨源访问。" },
        });
      }
      return ok({
        server: "zju-campus-agent",
        version: "0.1.0",
        isDev: deps.config.isDev,
        // 开发期返回 token，生产期为 null（由 Electron 注入或文件读取）
        accessToken: deps.config.isDev ? deps.config.accessToken : null,
        endpoints: {
          health: "/api/health",
          settings: "/api/settings",
        },
      });
    });
  };
}
