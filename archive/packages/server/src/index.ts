/**
 * 本地服务启动入口。
 *
 * 设计要点（见 ZJU_CAMPUS_AGENT_PROJECT.md 第 6.2 节）：
 * - 默认只监听 127.0.0.1，不绑公网。
 * - 启动时生成本地访问 token，前端调用 API 必须带 token。
 * - 通过 npm 包 login-zju 接入校园服务（在 zju-services 包内）。
 */

import { createServer } from "./server.js";
import { loadConfig, resolveAppDir } from "./config/env.js";
import { logger } from "./config/logger.js";
import { initStorage } from "./storage/db.js";
import { EncryptedFileCredentialStore } from "./auth/credentials.js";
import { createZjuServices } from "@zju-agent/zju-services";
import { createServicesContainer } from "./services.js";

async function main() {
  const appDir = resolveAppDir();
  const config = loadConfig(appDir);
  logger.info("启动目录", { appDir });

  const storage = await initStorage(appDir);
  const credentials = new EncryptedFileCredentialStore(appDir);
  const zju = createZjuServices();

  const services = createServicesContainer({
    config,
    storage,
    credentials,
    zju,
  });

  // 迁移：清理早期版本误存于明文 settings 表中的模型 apiKey（完整副本已在加密凭据库）
  const plainProviders = services.settings.get<
    Array<{ id: string; apiKey?: string }>
  >("model-providers");
  if ((plainProviders ?? []).some((p) => p.apiKey)) {
    services.settings.set(
      "model-providers",
      (plainProviders ?? []).map((p) => ({ ...p, apiKey: "" })),
    );
    logger.info("已清理明文 settings 表中的历史 apiKey");
  }

  const server = await createServer(services);

  try {
    await server.listen({
      host: config.host,
      port: config.port,
    });
    logger.info(`本地 API 服务已启动: http://${config.host}:${config.port}`);
    logger.info(`健康检查: http://${config.host}:${config.port}/api/health`);
    if (config.isDev) {
      logger.info(
        `开发期访问 token: ${config.accessToken.slice(0, 4)}…（前端经 /api/bootstrap 获取）`,
      );
    }
  } catch (err) {
    logger.error("服务启动失败", err);
    process.exit(1);
  }

  const shutdown = async (signal: string) => {
    logger.info(`收到 ${signal}，正在关闭服务…`);
    await server.close();
    storage.close();
    process.exit(0);
  };
  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

void main();
