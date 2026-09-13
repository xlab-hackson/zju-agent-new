/**
 * 系统托盘：开发期服务的唯一控制面板。
 */
import { Menu, Tray, nativeImage, type MenuItemConstructorOptions } from "electron";
import { TRAY_ICON_DATA_URL } from "./tray-icon.js";

export type TrayState = {
  widgetVisible: boolean;
  services: {
    label: string;
    port: number;
    ready: boolean;
    external: boolean;
  }[];
};

export type TrayActions = {
  openApp: () => void;
  toggleWidget: () => void;
  openLogs: () => void;
  restartServices: () => void;
  quit: () => void;
};

export type TrayController = {
  refresh: () => void;
  destroy: () => void;
};

function resolveTrayIcon() {
  return nativeImage.createFromDataURL(TRAY_ICON_DATA_URL);
}

export function createTray(
  actions: TrayActions,
  getState: () => TrayState,
): TrayController {
  const image = resolveTrayIcon();
  if (image.isEmpty()) {
    console.warn(
      "[tray] 托盘图标为空，请执行 node scripts/make-icon.mjs 重新生成 src/tray-icon.ts",
    );
  }

  const tray = new Tray(image);
  tray.setToolTip("浙大校园助手 · 开发服务");

  function buildStatusLine(state: TrayState): string {
    const parts = state.services.map((service) => {
      const suffix = service.external ? "外部" : service.ready ? "运行中" : "未就绪";
      return `${service.label} ${service.port} ${suffix}`;
    });
    return parts.join(" · ") || "服务未启动";
  }

  function refresh() {
    const state = getState();
    const template: MenuItemConstructorOptions[] = [
      { label: buildStatusLine(state), enabled: false },
      { type: "separator" },
      { label: "打开主界面", click: actions.openApp },
      {
        label: state.widgetVisible ? "隐藏桌面挂件" : "显示桌面挂件",
        click: actions.toggleWidget,
      },
      { label: "打开日志目录", click: actions.openLogs },
      { label: "重启服务", click: actions.restartServices },
      { type: "separator" },
      { label: "退出（停止服务）", click: actions.quit },
    ];
    tray.setContextMenu(Menu.buildFromTemplate(template));
    tray.setToolTip(`浙大校园助手 · ${buildStatusLine(state)}`);
  }

  // 左键单击切换挂件显示，双击打开主界面
  tray.on("click", actions.toggleWidget);
  tray.on("double-click", actions.openApp);

  refresh();

  return {
    refresh,
    destroy: () => tray.destroy(),
  };
}
