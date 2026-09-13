/**
 * 用 esbuild 打包 Electron 主进程和 preload 脚本。
 */
import * as esbuild from "esbuild";

const isDev = process.argv.includes("--dev");

await esbuild.build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "esm",
  outfile: "dist/main.js",
  external: ["electron", "better-sqlite3", "login-zju"],
  sourcemap: isDev,
  minify: !isDev,
});

await esbuild.build({
  entryPoints: ["src/preload.ts"],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "cjs",
  outfile: "dist/preload.js",
  external: ["electron"],
  sourcemap: isDev,
  minify: !isDev,
});

console.log("Main + preload built OK");
