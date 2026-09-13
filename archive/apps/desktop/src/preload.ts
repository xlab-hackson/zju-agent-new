/**
 * Preload 脚本：暴露安全的 API 给渲染进程。
 * 前端通过 HTTP + token 访问本机服务端。
 */

import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("electronAPI", {
  platform: process.platform,
  /** 桌面挂件专用（仅 launcher 模式下有实际效果） */
  widget: {
    /** 隐藏挂件（托盘菜单或点击挂件右上角关闭按钮） */
    hide: () => ipcRenderer.invoke("widget:hide") as Promise<void>,
    /** 用默认浏览器打开 Web 应用内的某个路径，如 "/courses" */
    openApp: (pathname?: string) =>
      ipcRenderer.invoke("widget:open-app", pathname ?? "/") as Promise<void>,
  },
});
