/**
 * Electron 主进程。
 *
 * 两种运行模式：
 * - 默认（桌面应用）：启动本地 Fastify 服务端，创建主窗口加载前端。
 * - `--launcher`（开发托管）：隐藏托管前后端开发服务 + 系统托盘 + 桌面挂件，
 *   由 start-dev.bat 调用，替代原先弹出的两个终端窗口。
 *
 * 服务端绑定 127.0.0.1:7788，仅本机可访问。
 */

import { app, BrowserWindow, ipcMain, shell } from "electron";
import { spawn, type ChildProcess } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { appDir, isDev, runDir, SERVER_URL, WEB_URL } from "./paths.js";
import { createDevLauncher, type DevLauncher } from "./launcher.js";
import { createTray, type TrayController } from "./tray.js";
import { createWidgetWindow } from "./widget-window.js";

const isLauncherMode = process.argv.includes("--launcher");

// launcher 使用独立的 userData，避免与桌面应用模式互抢单实例锁
if (isLauncherMode) {
  app.setPath("userData", path.join(app.getPath("appData"), "zju-campus-agent-launcher"));
}

let serverProcess: ChildProcess | null = null;

// ---------------- 桌面应用模式 ----------------

function getServerEntry(): string {
  if (isDev) {
    return path.resolve(appDir, "../../../packages/server/src/index.ts");
  }
  // 生产模式：server 是 extraResource，在 resources/server/
  return path.join(process.resourcesPath, "server", "index.js");
}

function getWebRoot(): string {
  if (isDev) return "http://localhost:5173";
  return `file://${path.join(appDir, "../web")}`;
}

function startServer(): Promise<void> {
  return new Promise((resolve, reject) => {
    const entry = getServerEntry();
    const cwd = path.resolve(appDir, "../../..");

    if (isDev) {
      // 开发模式：使用 tsx
      serverProcess = spawn("npx", ["tsx", "watch", entry], {
        cwd,
        env: { ...process.env, NODE_ENV: "development" },
        stdio: ["ignore", "pipe", "pipe"],
        windowsHide: true,
      });
    } else {
      // 生产模式：server 是 extraResource
      const serverDir = path.join(process.resourcesPath, "server");
      serverProcess = spawn(process.execPath, [entry], {
        cwd: serverDir,
        env: { ...process.env, NODE_ENV: "production" },
        stdio: ["ignore", "pipe", "pipe"],
        windowsHide: true,
      });
    }

    serverProcess.stdout?.on("data", (data: Buffer) => {
      const text = data.toString();
      process.stdout.write(`[server] ${text}`);
    });

    serverProcess.stderr?.on("data", (data: Buffer) => {
      const text = data.toString();
      process.stderr.write(`[server:err] ${text}`);
      // Fastify 启动成功会打印 listening 日志
      if (text.includes("listening") || text.includes("Server listening")) {
        resolve();
      }
    });

    serverProcess.on("error", (err) => {
      console.error("Server process error:", err);
      reject(err);
    });

    serverProcess.on("exit", (code) => {
      if (code !== 0 && code !== null) {
        console.error(`Server exited with code ${code}`);
        if (!isDev) reject(new Error(`Server exited: ${code}`));
      }
    });

    // 超时兜底：3 秒后尝试连接
    setTimeout(() => resolve(), 3000);
  });
}

async function waitForServer(url: string, maxRetries = 20): Promise<void> {
  for (let i = 0; i < maxRetries; i++) {
    try {
      const res = await fetch(`${url}/api/health`);
      if (res.ok) return;
    } catch {
      // 服务尚未就绪
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("Server failed to start within timeout");
}

async function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    title: "ZJU Campus Agent",
    webPreferences: {
      preload: path.join(appDir, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // 在默认浏览器打开外部链接
  win.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: "deny" };
  });

  const webRoot = getWebRoot();
  if (isDev) {
    win.loadURL(webRoot);
    win.webContents.openDevTools({ mode: "detach" });
  } else {
    // 生产模式：asar 内 dist/web/ → 加载 index.html
    const indexPath = path.join(appDir, "web/index.html");
    await win.loadFile(indexPath);
  }
}

// ---------------- launcher 模式 ----------------

let launcher: DevLauncher | null = null;
let trayController: TrayController | null = null;
let widgetWindow: BrowserWindow | null = null;
let quitting = false;
let launcherPidFile: string | null = null;

function recreateWidget() {
  if (widgetWindow && !widgetWindow.isDestroyed()) {
    widgetWindow.destroy();
  }
  console.log("[launcher] 创建挂件窗口");
  widgetWindow = createWidgetWindow();
  widgetWindow.on("closed", () => {
    widgetWindow = null;
    trayController?.refresh();
  });
  trayController?.refresh();
}

function showWidget() {
  if (widgetWindow && !widgetWindow.isDestroyed()) {
    widgetWindow.showInactive();
  } else {
    recreateWidget();
  }
  trayController?.refresh();
}

function toggleWidget() {
  if (widgetWindow && !widgetWindow.isDestroyed() && widgetWindow.isVisible()) {
    widgetWindow.hide();
    trayController?.refresh();
    return;
  }
  showWidget();
}

async function runLauncher() {
  if (!app.requestSingleInstanceLock()) {
    console.log("[launcher] 已有实例在运行，本次启动退出");
    app.quit();
    return;
  }

  app.on("second-instance", () => {
    showWidget();
    launcher?.openApp();
  });

  fs.mkdirSync(runDir, { recursive: true });
  launcherPidFile = path.join(runDir, "launcher.pid");
  fs.writeFileSync(launcherPidFile, String(process.pid), "utf8");

  launcher = createDevLauncher(() => trayController?.refresh());

  trayController = createTray(
    {
      openApp: () => launcher?.openApp(),
      toggleWidget,
      openLogs: () => {
        void shell.openPath(runDir);
      },
      restartServices: () => {
        void launcher?.restartAll();
      },
      quit: () => app.quit(),
    },
    () => ({
      widgetVisible:
        !!widgetWindow && !widgetWindow.isDestroyed() && widgetWindow.isVisible(),
      services: (launcher?.services() ?? []).map((service) => ({
        label: service.label,
        port: service.port,
        ready: service.ready,
        external: service.external,
      })),
    }),
  );

  // 挂件页面通过 preload 暴露的这两个通道与主进程交互
  ipcMain.handle("widget:hide", () => {
    widgetWindow?.hide();
    trayController?.refresh();
  });

  ipcMain.handle("widget:open-app", (_event, pathname: unknown) => {
    const suffix =
      typeof pathname === "string" && pathname.startsWith("/") ? pathname : "/";
    void shell.openExternal(new URL(suffix, WEB_URL).toString());
  });

  await launcher.start();

  // 等服务就绪后再建挂件窗口：否则首帧会加载失败（Vite 还没起来），
  // 日志里会留下 ERR_CONNECTION_REFUSED 的噪音。托盘图标在 start() 时已出现。
  const ready = await launcher.waitUntilReady();
  recreateWidget();
  if (ready) {
    launcher.openApp();
  }
  trayController.refresh();
}

// ---------------- 生命周期 ----------------

app.whenReady().then(async () => {
  if (isLauncherMode) {
    await runLauncher();
    return;
  }

  try {
    await startServer();
    console.log(`Waiting for server at ${SERVER_URL}...`);
    await waitForServer(SERVER_URL);
    console.log("Server ready, creating window...");
    await createWindow();
  } catch (err) {
    console.error("Failed to start:", err);
    // 即使服务端启动失败也打开窗口（可能是 dev 模式已单独启动服务端）
    if (isDev) {
      await createWindow();
    } else {
      app.quit();
    }
  }
});

app.on("window-all-closed", () => {
  // launcher 模式靠托盘常驻，关掉挂件不等于退出
  if (isLauncherMode) return;

  if (serverProcess) {
    serverProcess.kill("SIGTERM");
    serverProcess = null;
  }
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (isLauncherMode) return;
  if (BrowserWindow.getAllWindows().length === 0) {
    void createWindow();
  }
});

app.on("before-quit", (event) => {
  if (isLauncherMode) {
    if (quitting) return;
    event.preventDefault();
    quitting = true;
    void (async () => {
      console.log("[launcher] 正在停止后台服务…");
      await launcher?.stopAll();
      if (launcherPidFile) {
        fs.rmSync(launcherPidFile, { force: true });
      }
      app.quit();
    })();
    return;
  }

  if (serverProcess) {
    serverProcess.kill("SIGTERM");
    serverProcess = null;
  }
});
