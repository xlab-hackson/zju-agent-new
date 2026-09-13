/**
 * launcher 模式：在后台隐藏托管开发期的前后端服务。
 *
 * 设计要点：
 * - 子进程一律 `windowsHide: true`，避免弹出控制台窗口（也即用户看到的“两个终端”）。
 * - stdout/stderr 重定向到 `.run/<name>.log`，日志不再依赖窗口。
 * - 端口已被占用时复用现有进程（`external`），退出时不去动它。
 * - 停止时用 `taskkill /T /F` 杀整棵进程树：pnpm → node → tsx/vite 有多层子进程，
 *   单纯 child.kill() 会留下孤儿进程占着端口。
 */
import { execFile, spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { shell } from "electron";
import { repoRoot, runDir, SERVER_PORT, SERVER_URL, WEB_PORT, WEB_URL } from "./paths.js";

export type ServiceName = "server" | "web";

export type ServiceInfo = {
  name: ServiceName;
  label: string;
  port: number;
  /** pnpm 脚本名 */
  script: string;
  child: ChildProcess | null;
  /** 端口被本 launcher 之外的进程占用 */
  external: boolean;
  ready: boolean;
};

export type DevLauncher = {
  services: () => ServiceInfo[];
  allReady: () => boolean;
  start: () => Promise<void>;
  waitUntilReady: () => Promise<boolean>;
  stopAll: () => Promise<void>;
  restartAll: () => Promise<void>;
  openApp: () => void;
};

function log(message: string) {
  console.log(`[launcher] ${message}`);
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** 探测 127.0.0.1:port 是否有进程在监听 */
function isPortListening(port: number, timeoutMs = 500): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    const finish = (value: boolean) => {
      socket.destroy();
      resolve(value);
    };
    socket.setTimeout(timeoutMs);
    socket.once("connect", () => finish(true));
    socket.once("timeout", () => finish(false));
    socket.once("error", () => finish(false));
  });
}

/** 轮询直到 HTTP 可用 */
async function waitForHttp(url: string, timeoutMs: number): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(url);
      if (res.ok) return true;
    } catch {
      // 服务尚未就绪
    }
    await delay(400);
  }
  return false;
}

function killTree(pid: number): Promise<void> {
  return new Promise((resolve) => {
    if (process.platform === "win32") {
      execFile("taskkill", ["/PID", String(pid), "/T", "/F"], { windowsHide: true }, () =>
        resolve(),
      );
      return;
    }
    try {
      process.kill(pid, "SIGTERM");
    } catch {
      // 进程可能已退出
    }
    resolve();
  });
}

export function createDevLauncher(onChange: () => void): DevLauncher {
  const services: ServiceInfo[] = [
    { name: "server", label: "后端", port: SERVER_PORT, script: "dev:server", child: null, external: false, ready: false },
    { name: "web", label: "前端", port: WEB_PORT, script: "dev:web", child: null, external: false, ready: false },
  ];

  function spawnService(info: ServiceInfo): ChildProcess {
    fs.mkdirSync(runDir, { recursive: true });
    const logFd = fs.openSync(path.join(runDir, `${info.name}.log`), "a");
    const env = {
      ...process.env,
      NODE_ENV: "development",
      NO_COLOR: "1",
      FORCE_COLOR: "0",
    };
    const options = {
      cwd: repoRoot,
      env,
      windowsHide: true,
      stdio: ["ignore", logFd, logFd] as ["ignore", number, number],
    };
    const child =
      process.platform === "win32"
        ? spawn("cmd.exe", ["/d", "/s", "/c", "pnpm", info.script], options)
        : spawn("pnpm", [info.script], options);

    log(`启动 ${info.label}：pnpm ${info.script}（日志 .run/${info.name}.log）`);

    child.on("error", (err) => {
      log(`${info.label} 启动失败：${err.message}`);
      info.child = null;
      info.ready = false;
      onChange();
    });

    child.on("exit", (code, signal) => {
      if (info.child === child) {
        info.child = null;
        info.ready = false;
        log(`${info.label} 已退出（code=${code ?? "null"} signal=${signal ?? "null"}）`);
        onChange();
      }
    });

    return child;
  }

  async function start() {
    for (const info of services) {
      if (await isPortListening(info.port)) {
        info.external = true;
        info.ready = true;
        log(`${info.label} 端口 ${info.port} 已被占用，复用现有进程`);
        continue;
      }
      info.external = false;
      info.ready = false;
      info.child = spawnService(info);
    }
    onChange();
  }

  async function waitUntilReady(): Promise<boolean> {
    const results = await Promise.all([
      waitForHttp(`${SERVER_URL}/api/health`, 40_000),
      waitForHttp(`${WEB_URL}/`, 40_000),
    ]);
    services.forEach((info, index) => {
      const ok = results[index] ?? false;
      if (info.ready !== ok) {
        info.ready = ok;
      }
      if (!ok) {
        log(`${info.label} 在超时时间内未就绪，请查看 .run/${info.name}.log`);
      }
    });
    onChange();
    return services.every((info) => info.ready);
  }

  async function stopAll() {
    for (const info of services) {
      if (info.child?.pid) {
        await killTree(info.child.pid);
      }
      info.child = null;
      info.ready = false;
    }
    onChange();
  }

  async function restartAll() {
    log("重启全部服务…");
    await stopAll();
    await delay(600);
    await start();
    const ok = await waitUntilReady();
    log(ok ? "服务已重启" : "服务重启后仍未就绪，请查看日志");
  }

  return {
    services: () => services,
    allReady: () => services.every((info) => info.ready),
    start,
    waitUntilReady,
    stopAll,
    restartAll,
    openApp: () => {
      void shell.openExternal(WEB_URL);
    },
  };
}
