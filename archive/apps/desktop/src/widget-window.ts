/**
 * 桌面挂件窗口：无边框、半透明、始终置顶、不占任务栏。
 *
 * 背景说明（2026-09-08 实测，详见 docs/widget-material-comparison.md）：
 * Windows 11 + Electron 的 `backgroundMaterial('acrylic')` 在「无边框 + 透明 + 置顶」
 * 组合下只会渲染成纯灰 #545454（Electron 33 / 38 均如此），所以这里不再请求系统材质，
 * 半透明效果全部由页面 CSS 完成。
 */
import { BrowserWindow, screen, shell } from "electron";
import path from "node:path";
import { appDir, isDev, WEB_URL } from "./paths.js";

export const WIDGET_WIDTH = 380;
export const WIDGET_HEIGHT = 560;

/** 距屏幕右边缘与工作区边界的留白（DIP） */
const EDGE_MARGIN = 16;

export function createWidgetWindow(): BrowserWindow {
  const { workArea } = screen.getPrimaryDisplay();
  const x = Math.round(workArea.x + workArea.width - WIDGET_WIDTH - EDGE_MARGIN);
  const y = Math.round(workArea.y + Math.max(0, (workArea.height - WIDGET_HEIGHT) / 2));
  console.log(
    `[widget] 位置 (${x}, ${y})，尺寸 ${WIDGET_WIDTH}×${WIDGET_HEIGHT}；工作区 (${workArea.x}, ${workArea.y}) ${workArea.width}×${workArea.height}`,
  );

  const win = new BrowserWindow({
    width: WIDGET_WIDTH,
    height: WIDGET_HEIGHT,
    x,
    y,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    resizable: false,
    maximizable: false,
    minimizable: false,
    fullscreenable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    hasShadow: false,
    show: false,
    title: "浙大校园助手 · 挂件",
    webPreferences: {
      preload: path.join(appDir, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  win.setAlwaysOnTop(true, "floating");

  // 挂件内点击条目 → 用默认浏览器打开 Web 应用
  win.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: "deny" };
  });

  const target = isDev
    ? { kind: "url" as const, value: `${WEB_URL}/widget.html` }
    : { kind: "file" as const, value: path.join(appDir, "web/widget.html") };

  const load = () =>
    target.kind === "url" ? win.loadURL(target.value) : win.loadFile(target.value);

  // 挂件窗口创建时 Vite 往往还没就绪：失败就重试，成功后才显示，
  // 这样桌面上不会出现 Chromium 的“无法访问”错误页，也避开透明窗口黑闪。
  let loaded = false;
  let attempts = 0;
  const MAX_ATTEMPTS = 40;

  win.webContents.on("did-finish-load", () => {
    loaded = true;
    if (!win.isVisible()) {
      win.showInactive();
    }
  });

  win.webContents.on(
    "did-fail-load",
    (_event, errorCode, errorDescription, validatedURL, isMainFrame) => {
      // -3 = ERR_ABORTED（导航被新的加载取消），不算失败
      if (!isMainFrame || loaded || errorCode === -3) return;
      attempts += 1;
      if (attempts > MAX_ATTEMPTS) {
        console.error(
          `[widget] 挂件页面加载失败（${errorDescription}）：${validatedURL}`,
        );
        return;
      }
      setTimeout(() => {
        if (!win.isDestroyed()) void load();
      }, 1200);
    },
  );

  void load();

  return win;
}
