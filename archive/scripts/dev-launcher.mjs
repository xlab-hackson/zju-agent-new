/**
 * 开发模式后台启动器（由 start-dev.bat 调用）。
 *
 * 职责：
 *   1. 用 esbuild 构建 Electron 主进程 / preload；
 *   2. 探测 7788 / 5173 端口占用情况（仅用于提示）；
 *   3. 以 detached + windowsHide 方式启动 Electron launcher，
 *      随后本脚本退出，bat 窗口关闭 → 任务栏不再有常驻终端。
 *
 * Electron launcher 自己负责：隐藏托管 pnpm dev:server / dev:web、
 * 托盘图标、桌面挂件、服务就绪后打开浏览器。
 */
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const desktopDir = path.join(repoRoot, "apps", "desktop");
const runDir = path.join(repoRoot, ".run");
const launcherLog = path.join(runDir, "launcher.log");
const launcherPidFile = path.join(runDir, "launcher.pid");

const SERVER_PORT = 7788;
const WEB_PORT = 5173;

function fail(message) {
  console.error(`[错误] ${message}`);
  process.exit(1);
}

function isPortListening(port, timeoutMs = 400) {
  return new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    const finish = (value) => {
      socket.destroy();
      resolve(value);
    };
    socket.setTimeout(timeoutMs);
    socket.once("connect", () => finish(true));
    socket.once("timeout", () => finish(false));
    socket.once("error", () => finish(false));
  });
}

function isProcessAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function readRunningPid() {
  try {
    const pid = Number.parseInt(fs.readFileSync(launcherPidFile, "utf8").trim(), 10);
    return Number.isInteger(pid) && pid > 0 && isProcessAlive(pid) ? pid : null;
  } catch {
    return null;
  }
}

function tailLog(lines = 15) {
  try {
    const content = fs.readFileSync(launcherLog, "utf8").trimEnd();
    return content.split(/\r?\n/).slice(-lines).join("\n");
  } catch {
    return "(暂无日志)";
  }
}

function resolveElectronBinary() {
  const requireFromDesktop = createRequire(path.join(desktopDir, "package.json"));
  let binary;
  try {
    binary = requireFromDesktop("electron");
  } catch {
    fail("未找到 electron 依赖，请先在项目根目录执行 pnpm install。");
  }
  if (typeof binary !== "string" || !fs.existsSync(binary)) {
    fail("Electron 可执行文件缺失，请执行 pnpm install 重新下载。");
  }
  return binary;
}

async function main() {
  fs.mkdirSync(runDir, { recursive: true });

  const runningPid = readRunningPid();
  if (runningPid) {
    console.log(`[跳过] 托盘与挂件已在运行（PID ${runningPid}）。`);
    console.log("        如需停止：双击 stop-dev.bat，或使用托盘菜单「退出」。");
    return;
  }

  const electronBinary = resolveElectronBinary();

  console.log("[构建] 编译 Electron 主进程…");
  const build = spawnSync(process.execPath, ["scripts/build-main.js"], {
    cwd: desktopDir,
    stdio: "inherit",
  });
  if (build.status !== 0) {
    fail("主进程构建失败，请检查上方 esbuild 输出。");
  }

  const [serverUp, webUp] = await Promise.all([
    isPortListening(SERVER_PORT),
    isPortListening(WEB_PORT),
  ]);
  console.log(
    serverUp
      ? `[跳过] 后端 7788 已在运行，将复用现有进程。`
      : `[启动] 后端 7788（pnpm dev:server，隐藏运行）`,
  );
  console.log(
    webUp
      ? `[跳过] 前端 5173 已在运行，将复用现有进程。`
      : `[启动] 前端 5173（pnpm dev:web，隐藏运行）`,
  );
  console.log("[启动] 系统托盘与桌面挂件…");

  const logFd = fs.openSync(launcherLog, "a");
  const child = spawn(electronBinary, [desktopDir, "--launcher"], {
    cwd: desktopDir,
    detached: true,
    windowsHide: true,
    stdio: ["ignore", logFd, logFd],
    env: { ...process.env, NODE_ENV: "development" },
  });
  child.unref();

  if (!child.pid) {
    fail("无法启动 Electron launcher 进程。");
  }
  fs.writeFileSync(launcherPidFile, String(child.pid), "utf8");

  // 短暂等待，捕捉“启动即崩”的情况
  await new Promise((resolve) => setTimeout(resolve, 900));
  if (!isProcessAlive(child.pid)) {
    console.error("[错误] Electron launcher 启动后立即退出，最近日志：");
    console.error(tailLog());
    fail("启动失败。");
  }

  console.log(`[完成] 服务与挂件已转入后台（PID ${child.pid}）。`);
  console.log(`        日志目录：.run\\（launcher.log / server.log / web.log）`);
}

await main();
