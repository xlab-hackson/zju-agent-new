/**
 * AuthSessionManager — 统一登录管理器。
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 7.1 节。
 *
 * - ZJUAM 实例由统一认证账号密码创建。
 * - COURSES / CLASSROOM / ZDBK 等服务通过同一个 ZJUAM 实例创建（懒加载）。
 * - 登录失败转换为结构化错误。
 * - 不在日志中输出密码、cookie、API Key。
 */

import type { CredentialStore } from "./credentials.js";
import {
  AppError,
  ErrorCode,
  type AuthStatus,
  type CredentialStatus,
  type ZjuCredential,
  maskUsername,
} from "@zju-agent/core";
import type {
  ZjuServices,
  ZjuServiceAdapters,
  ZjuServiceInstances,
} from "@zju-agent/zju-services";
import { logger } from "../config/logger.js";

const CRED_KEY = "zju-credential";

export class AuthSessionManager {
  private cachedUsername: string | null = null;

  constructor(
    private credentials: CredentialStore,
    private zju: ZjuServices,
  ) {}

  async setCredential(input: ZjuCredential): Promise<void> {
    if (!input.username || !input.password) {
      throw new AppError(
        ErrorCode.ZJU_CREDENTIAL_MISSING,
        "账号或密码为空。",
      );
    }
    await this.credentials.set<ZjuCredential>(CRED_KEY, input);
    this.cachedUsername = input.username;
    // 修改密码后清除旧 session
    await this.zju.reset();
    logger.info("ZJU 凭据已保存", { username: maskUsername(input.username) });
  }

  async getCredential(): Promise<ZjuCredential | null> {
    if (this.cachedUsername) {
      // 仍需从存储读取完整凭据
    }
    return this.credentials.get<ZjuCredential>(CRED_KEY);
  }

  /** 验证统一身份认证，不强制登录各服务 */
  async validateCredential(): Promise<AuthStatus> {
    const cred = await this.getCredential();
    if (!cred) {
      return {
        ok: false,
        message: "尚未配置 ZJU 账号。",
      };
    }
    try {
      const ok = await this.zju.loginZjuam(cred.username, cred.password);
      return {
        ok,
        username: cred.username,
        services: ok ? { zjuam: true } : undefined,
      };
    } catch (err) {
      const message =
        err instanceof Error ? err.message : "统一身份认证失败。";
      logger.warn("ZJU 登录验证失败", { message });
      return {
        ok: false,
        username: cred.username,
        message,
      };
    }
  }

  /** 获取已登录的服务实例（懒加载） */
  async getServiceInstances(): Promise<ZjuServiceInstances> {
    const cred = await this.getCredential();
    if (!cred) {
      throw new AppError(
        ErrorCode.ZJU_CREDENTIAL_MISSING,
        "尚未配置 ZJU 账号，无法访问校园服务。",
        { retryable: false },
      );
    }
    return this.zju.getInstances(cred.username, cred.password);
  }

  /** 获取领域适配器（确保已登录）。路由读取校园数据时统一走这里。 */
  async getServiceAdapters(): Promise<ZjuServiceAdapters> {
    const cred = await this.getCredential();
    if (!cred) {
      throw new AppError(
        ErrorCode.ZJU_CREDENTIAL_MISSING,
        "尚未配置 ZJU 账号，无法访问校园服务。",
        { retryable: false },
      );
    }
    // 确保已登录并构建适配器
    await this.zju.getInstances(cred.username, cred.password);
    return this.zju.getAdapters();
  }

  async clearSessions(): Promise<void> {
    await this.zju.reset();
    logger.info("ZJU 服务 session 已清除");
  }

  async logout(): Promise<void> {
    await this.zju.reset();
    await this.credentials.delete(CRED_KEY);
    this.cachedUsername = null;
    logger.info("ZJU 凭据已删除，已登出");
  }

  /** 前端可获得的脱敏凭据状态 */
  async getStatus(): Promise<CredentialStatus> {
    const cred = await this.getCredential();
    // 从加密凭据库读取模型 provider 的真实 apiKey 状态
    const providers = await this.credentials.get<
      Array<{ name?: string; apiKey?: string; enabled?: boolean }>
    >("model-providers");
    const enabledWithKey = (providers ?? []).find((p) => p.enabled && p.apiKey);
    return {
      hasZjuCredential: !!cred,
      zjuUsernameMasked: cred ? maskUsername(cred.username) : undefined,
      hasModelApiKey: !!enabledWithKey,
      modelProviderName: enabledWithKey?.name,
    };
  }
}
