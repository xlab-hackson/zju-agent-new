# 旧 Web/Electron/Node 实现归档

这里保留迁移前的 React Web、Electron 桌面壳和 Node 服务，仅作为历史实现、协议参考和视觉/交互对照。

当前主实现已经位于仓库根目录，是 Flutter 客户端。除非明确维护旧实现，否则不要在本目录继续扩展功能。

旧实现的开发命令请在本目录执行：

```powershell
pnpm install
pnpm dev:server
pnpm dev:web
pnpm typecheck
pnpm test
pnpm lint
pnpm build
```

目录结构：

- `apps/web`：React 18 + Vite 前端及旧 Web 挂件。
- `apps/desktop`：Electron 壳、托盘和旧桌面挂件。
- `packages/server`：Fastify 服务、SSE Agent、缓存和加密凭据。
- `packages/zju-services`：服务端 `login-zju` 适配层。
