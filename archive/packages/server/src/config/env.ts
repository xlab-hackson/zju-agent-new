import { join } from "node:path";
import { homedir, platform } from "node:os";
import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";

export type ServerConfig = {
  host: string;
  port: number;
  appDir: string;
  dbPath: string;
  downloadDir: string;
  /** 本地访问 token，前端调用 API 必须携带 */
  accessToken: string;
  isDev: boolean;
};

const DEFAULT_PORT = 7788;

/** 解析应用数据目录。本地优先应用，数据放在用户目录下。 */
export function resolveAppDir(): string {
  const home = homedir();
  const base =
    platform() === "win32"
      ? process.env.APPDATA ?? join(home, "AppData", "Roaming")
      : platform() === "darwin"
        ? join(home, "Library", "Application Support")
        : home;
  const dir = join(base, ".zju-campus-agent");
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  return dir;
}

/** 加载服务配置。token 持久化到 appDir/.token 文件。 */
export function loadConfig(appDir: string): ServerConfig {
  const isDev = process.env.NODE_ENV !== "production";
  const port = Number(process.env.ZJU_AGENT_PORT ?? DEFAULT_PORT);
  // 永远只绑回环地址，避免监听公网
  const host = "127.0.0.1";

  const tokenFile = join(appDir, ".token");
  let accessToken = "";
  if (existsSync(tokenFile)) {
    accessToken = readFileSync(tokenFile, "utf8").trim();
  }
  if (!accessToken) {
    accessToken = randomBytes(24).toString("hex");
    writeFileSync(tokenFile, accessToken, { mode: 0o600 });
  }

  const downloadDir = join(appDir, "downloads");
  if (!existsSync(downloadDir)) {
    mkdirSync(downloadDir, { recursive: true });
  }

  return {
    host,
    port,
    appDir,
    dbPath: join(appDir, "agent.db"),
    downloadDir,
    accessToken,
    isDev,
  };
}

/**
 * 轮换本地访问 token：生成新随机值、写入 .token 文件（0o600），
 * 并同步更新内存中的 config，使旧 token 立即失效。
 */
export function rotateAccessToken(config: ServerConfig): string {
  const token = randomBytes(24).toString("hex");
  writeFileSync(join(config.appDir, ".token"), token, { mode: 0o600 });
  config.accessToken = token;
  return token;
}
