/**
 * 复制 Vite web build 到 Electron dist 目录。
 */
import fs from "fs";
import path from "path";

const webDist = path.resolve("../../apps/web/dist");
const webDest = path.resolve("dist/web");

if (!fs.existsSync(webDist)) {
  console.error(`Web dist not found at ${webDist}`);
  console.error("Run: pnpm --filter @zju-agent/web build");
  process.exit(1);
}

// 清理旧文件
if (fs.existsSync(webDest)) {
  fs.rmSync(webDest, { recursive: true });
}
fs.mkdirSync(webDest, { recursive: true });

// 拷贝
fs.cpSync(webDist, webDest, { recursive: true });

// 统计
const files = fs.readdirSync(webDest, { recursive: true });
console.log(`Copied ${files.length} files from web dist to dist/web`);
