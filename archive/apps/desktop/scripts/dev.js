/**
 * 开发模式启动：先构建主进程，然后启动 Electron。
 * 需要单独运行 pnpm dev:server 和 pnpm dev:web。
 */
import { spawn } from "child_process";
import { build } from "esbuild";

// 快速构建 main + preload（不 minify）
await build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "esm",
  outfile: "dist/main.js",
  external: ["electron", "better-sqlite3", "login-zju"],
  sourcemap: true,
});

await build({
  entryPoints: ["src/preload.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  outfile: "dist/preload.js",
  external: ["electron"],
  sourcemap: true,
});

console.log("Built main + preload, launching Electron...");

const electron = spawn("npx", ["electron", "."], {
  stdio: "inherit",
  env: { ...process.env, NODE_ENV: "development" },
});

electron.on("close", (code) => process.exit(code ?? 0));
