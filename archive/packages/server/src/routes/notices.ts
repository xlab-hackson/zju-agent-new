/**
 * 学校通知公告路由：素质拓展平台 + 教务系统·通知公告。
 * 两个均为免登录公开源，与浙大凭据无关，NoticeService 直接挂在服务容器上。
 *
 * 路由：
 *   GET /api/zju/notices — 合并两源最近通知（缓存 30 分钟，refresh=1 强制刷新）
 */

import type { FastifyPluginAsync } from "fastify";
import { wrap, type NoticeFetchResult } from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";

export const NOTICES_CACHE_KEY = "notices:all";
export const NOTICES_CACHE_TTL_MS = 30 * 60_000;

export function noticesRoutes(
  deps: ServicesContainer & { config: ServerConfig },
): FastifyPluginAsync {
  return async (app) => {
    app.get<{
      Querystring: { limit?: string; refresh?: string };
    }>("/notices", async (req) => {
      return wrap(async () => {
        const limit = clampLimit(req.query.limit);
        const refresh = req.query.refresh === "1";
        if (!refresh) {
          const cached = deps.cache.get<NoticeFetchResult>(NOTICES_CACHE_KEY);
          if (cached) return cached;
        }
        const result = await deps.notices.getAllNotices(limit);
        deps.cache.set(NOTICES_CACHE_KEY, result, NOTICES_CACHE_TTL_MS);
        return result;
      });
    });
  };
}

function clampLimit(raw?: string): number {
  const n = Number(raw ?? "");
  if (!Number.isFinite(n) || n <= 0) return 15;
  return Math.min(Math.floor(n), 50);
}
