import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// 前端默认连接本机后端（127.0.0.1:7788）。
// Vite dev server 通过代理转发，避免浏览器跨域与混合内容问题。
const BACKEND_URL =
  process.env.ZJU_AGENT_BACKEND ?? "http://127.0.0.1:7788";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: false,
    proxy: {
      "/api": {
        target: BACKEND_URL,
        changeOrigin: false,
        // 开发期不写 token 到代理头；前端经 /api/bootstrap 自取 token 后注入
      },
    },
  },
  // 便于 Electron/Capacitor 复用：相对 base
  base: "./",
  build: {
    outDir: "dist",
    sourcemap: true,
    rollupOptions: {
      input: {
        // 主应用
        index: "index.html",
        // 桌面挂件（Electron 独立窗口加载，不套主应用外壳）
        widget: "widget.html",
      },
    },
  },
});
