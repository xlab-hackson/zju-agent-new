/**
 * 主进程共享路径与常量。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { app } from "electron";

/** dist/ 目录（bundle 所在目录） */
export const appDir = path.dirname(fileURLToPath(import.meta.url));

export const isDev =
  process.env.NODE_ENV === "development" || !app.isPackaged;

export const SERVER_PORT = 7788;
export const WEB_PORT = 5173;
export const SERVER_URL = `http://127.0.0.1:${SERVER_PORT}`;
export const WEB_URL = `http://localhost:${WEB_PORT}`;

/** 仓库根目录：开发期由 dist/ 上溯三级；打包后回退到 userData */
export const repoRoot = (() => {
  const candidate = path.resolve(appDir, "../../..");
  if (fs.existsSync(path.join(candidate, "pnpm-workspace.yaml"))) {
    return candidate;
  }
  return app.getPath("userData");
})();

/** 开发期运行时目录（日志 / PID），已在 .gitignore 中 */
export const runDir = path.join(repoRoot, ".run");
