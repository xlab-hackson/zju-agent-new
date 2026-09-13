/**
 * 本地访问 token 鉴权中间件。
 * 前端调用 API 必须在 Authorization 头携带 Bearer token。
 * 仅二进制预览路由（<img>/<iframe> 无法设 header）允许 ?token= 回退。
 */

import type { FastifyRequest, FastifyReply } from "fastify";
import { createHash, timingSafeEqual } from "node:crypto";
import type { ServerConfig } from "../config/env.js";
import { ErrorCode } from "@zju-agent/core";
import { fail } from "@zju-agent/core";

/** 不需要鉴权的路由前缀 */
const PUBLIC_PREFIXES = ["/api/health", "/api/bootstrap"];

/** 允许 ?token= query 回退的路径范围：仅下载预览 */
const PREVIEW_TOKEN_PREFIX = "/api/files/downloads/";

/** 恒定时间比较（先哈希到固定长度，规避长度差异与时序侧信道） */
function tokenEquals(a: string, b: string): boolean {
  const ha = createHash("sha256").update(a).digest();
  const hb = createHash("sha256").update(b).digest();
  return timingSafeEqual(ha, hb);
}

export function createAuthMiddleware(config: ServerConfig) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const url = req.url.split("?")[0] ?? req.url;
    if (PUBLIC_PREFIXES.some((p) => url === p || url.startsWith(p + "/"))) {
      return;
    }
    const auth = req.headers.authorization;
    // token 优先从 header 取；仅二进制资源（图片/PDF 内联预览）无法设 header，回退 query
    let token = auth?.startsWith("Bearer ") ? auth.slice(7) : null;
    if (
      !token &&
      url.startsWith(PREVIEW_TOKEN_PREFIX) &&
      url.endsWith("/preview")
    ) {
      const q = req.query as { token?: string } | undefined;
      if (q && typeof q === "object" && q.token) token = q.token;
    }
    const valid = token !== null && tokenEquals(token, config.accessToken);
    if (!valid) {
      const body = fail(ErrorCode.UNAUTHORIZED, "本地访问 token 无效或缺失。");
      return reply.code(401).send(body);
    }
  };
}
