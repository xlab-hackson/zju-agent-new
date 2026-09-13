/**
 * 用 esbuild 打包服务端代码。
 * better-sqlite3 是原生模块，标记为 external。
 * login-zju、fastify 等纯 JS 包会被内联到 bundle 中。
 */
import * as esbuild from "esbuild";
import fs from "fs";
import path from "path";

const isDev = process.argv.includes("--dev");
const outDir = "dist/server";

fs.mkdirSync(outDir, { recursive: true });

const serverEntry = path.resolve("../../packages/server/src/index.ts");

await esbuild.build({
  entryPoints: [serverEntry],
  bundle: true,
  platform: "node",
  target: "node20",
  format: "esm",
  outfile: path.join(outDir, "index.js"),
  external: [
    // 原生模块，不可打包
    "better-sqlite3",
  ],
  sourcemap: isDev,
  minify: !isDev,
  banner: {
    js: `import { createRequire } from 'module'; const require = createRequire(import.meta.url);`,
  },
});

// 复制原生模块到 server 目录
// pnpm monorepo 中，原生模块在根 node_modules 下（可能经过 symlink）
const nativeDeps = ["better-sqlite3"];
const searchPaths = [
  path.resolve("../../node_modules"),           // 根 node_modules
  path.resolve("../../packages/server/node_modules"), // server 包自己的 node_modules
];

for (const dep of nativeDeps) {
  let src = null;
  for (const base of searchPaths) {
    const candidate = path.join(base, dep);
    if (fs.existsSync(candidate)) {
      src = fs.realpathSync(candidate); // 解析 symlink
      break;
    }
  }
  if (!src) {
    // pnpm 的 .pnpm 目录
    const pnpmDir = path.resolve("../../node_modules/.pnpm");
    if (fs.existsSync(pnpmDir)) {
      const entries = fs.readdirSync(pnpmDir);
      const match = entries.find((e) => e.startsWith(`${dep}@`));
      if (match) {
        src = path.join(pnpmDir, match, "node_modules", dep);
      }
    }
  }
  if (src && fs.existsSync(src)) {
    const dst = path.join(outDir, "node_modules", dep);
    fs.rmSync(dst, { recursive: true, force: true });
    fs.cpSync(src, dst, { recursive: true, dereference: true });
    console.log(`Copied native dep: ${dep} (from ${src})`);
  } else {
    console.warn(`WARNING: Native dep not found: ${dep}`);
  }
}

// 验证 bundle 大小（太小说明没打包进去）
const stat = fs.statSync(path.join(outDir, "index.js"));
const sizeMB = (stat.size / (1024 * 1024)).toFixed(1);
console.log(`Server bundle: ${sizeMB} MB`);
