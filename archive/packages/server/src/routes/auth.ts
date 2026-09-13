/**
 * 认证路由：
 *   POST /api/auth/validate  — 验证 ZJU 统一身份认证
 *   GET  /api/auth/status    — 当前登录状态
 *   POST /api/auth/logout    — 清除凭据与 session
 *
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 10.1 节。
 */

import type { FastifyPluginAsync } from "fastify";
import { wrap, maskUsername, ErrorCode } from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";
import { rotateAccessToken } from "../config/env.js";
import { logger } from "../config/logger.js";
import { createRateLimiter } from "../util/rate-limit.js";

/** 认证接口限流：防本地 API 被爆破 ZJU 密码 */
const authLimiter = createRateLimiter({ windowMs: 60_000, max: 10 });

export function authRoutes(
  deps: ServicesContainer & { config: ServerConfig },
): FastifyPluginAsync {
  return async (app) => {
    // POST /api/auth/validate
    // 可选 body: { username, password }；不传则用已保存凭据
    app.post<{ Body?: { username?: string; password?: string } }>(
      "/validate",
      async (req, reply) => {
        if (!authLimiter.check(req.ip)) {
          return reply.code(429).send({
            ok: false,
            error: {
              code: ErrorCode.RATE_LIMITED,
              message: "尝试过于频繁，请稍后再试。",
            },
          });
        }
        return wrap(async () => {
          // 若请求体携带账号密码，则先保存再验证（便于向导「输入即验证」）
          const body = req.body ?? {};
          if (body.username && body.password) {
            await deps.auth.setCredential({
              username: body.username,
              password: body.password,
            });
          }
          const status = await deps.auth.validateCredential();
          if (status.ok) {
            logger.info("ZJU 登录验证成功", {
              username: status.username ? maskUsername(status.username) : undefined,
            });
          } else {
            logger.warn("ZJU 登录验证失败", { message: status.message });
          }
          // 学号脱敏后返回
          return {
            ...status,
            username: status.username ? maskUsername(status.username) : undefined,
          };
        });
      },
    );

    // GET /api/auth/status — 返回脱敏登录状态
    app.get("/status", async () => {
      return wrap(async () => {
        const status = await deps.auth.validateCredential();
        // 学号脱敏，避免完整学号出现在接口响应中
        return {
          ...status,
          username: status.username ? maskUsername(status.username) : undefined,
        };
      });
    });

    // POST /api/auth/logout — 清除凭据与 session，并轮换本地访问 token
    app.post("/logout", async () => {
      return wrap(async () => {
        await deps.auth.logout();
        // 轮换 token：登出前的旧 token（含任何泄露副本）立即失效
        rotateAccessToken(deps.config);
        logger.info("本地访问 token 已轮换");
        return { ok: true };
      });
    });
  };
}
