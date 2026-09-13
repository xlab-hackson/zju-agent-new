/// <reference types="vite/client" />

declare module "*.css";

/** Electron preload 暴露的 API（仅桌面端存在，浏览器中为 undefined） */
interface Window {
  electronAPI?: {
    platform: string;
    widget: {
      hide: () => Promise<void>;
      openApp: (pathname?: string) => Promise<void>;
    };
  };
}
