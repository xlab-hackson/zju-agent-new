/**
 * 停止 start-dev.bat 启动的后台服务（托盘与前后端）。
 *
 * 停止顺序：
 *   1. 读取 .run/launcher.pid，taskkill /T /F 杀掉整棵 Electron 进程树
 *      （Electron 退出时还会自行回收它 spawn 的 pnpm/tsx/vite 子进程）；
 *   2. 兜底：按端口 7788 / 5173 反查残留 PID 再杀一遍。
 */
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const runDir = path.join(repoRoot, ".run");
const launcherPidFile = path.join(runDir, "launcher.pid");

const PORTS = [7788, 5173];
const isWindows = process.platform === "win32";

function killTree(pid) {
  try {
    if (isWindows) {
      execFileSync("taskkill", ["/PID", String(pid), "/T", "/F"], {
        windowsHide: true,
        stdio: "ignore",
      });
    } else {
      process.kill(pid, "SIGTERM");
    }
    return true;
  } catch {
    return false;
  }
}

/** 按端口反查监听进程 PID（Windows: netstat -ano） */
function pidsOnPort(port) {
  if (!isWindows) return [];
  try {
    const output = execFileSync("netstat", ["-ano"], {
      encoding: "utf8",
      windowsHide: true,
    });
    const pids = new Set();
    for (const line of output.split(/\r?\n/)) {
      const match = /^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)/.exec(line);
      if (match && Number.parseInt(match[1], 10) === port) {
        pids.add(Number.parseInt(match[2], 10));
      }
    }
    return [...pids];
  } catch {
    return [];
  }
}

function readLauncherPid() {
  try {
    const pid = Number.parseInt(fs.readFileSync(launcherPidFile, "utf8").trim(), 10);
    return Number.isInteger(pid) && pid > 0 ? pid : null;
  } catch {
    return null;
  }
}

function main() {
  let stopped = 0;

  const launcherPid = readLauncherPid();
  if (launcherPid) {
    if (killTree(launcherPid)) {
      console.log(`[停止] 托盘与挂件进程树（PID ${launcherPid}）`);
      stopped++;
    } else {
      console.log(`[跳过] PID ${launcherPid} 已不存在`);
    }
  } else {
    console.log("[跳过] 未找到 .run/launcher.pid");
  }

  for (const port of PORTS) {
    for (const pid of pidsOnPort(port)) {
      if (killTree(pid)) {
        console.log(`[停止] 端口 ${port} 上的残留进程（PID ${pid}）`);
        stopped++;
      }
    }
  }

  fs.rmSync(launcherPidFile, { force: true });

  if (stopped === 0) {
    console.log("[完成] 没有发现正在运行的服务。");
  } else {
    console.log(`[完成] 已停止 ${stopped} 个进程，端口 7788 / 5173 应已释放。`);
  }
}

main();
