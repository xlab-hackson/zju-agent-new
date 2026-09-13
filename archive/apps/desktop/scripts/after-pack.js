/**
 * electron-builder afterPack hook：将 web 前端构建产物拷贝到 app 资源目录。
 */
import fs from "fs";
import path from "path";

export default async function afterPack(context) {
  const { appOutDir, packager } = context;
  const platform = packager.platform.name;

  // 确定 asar 解包后的 resources 路径
  const resourcesPath = path.join(
    appOutDir,
    packager.appInfo.productFilename + (platform === "darwin" ? ".app/Contents/Resources" : "/resources"),
  );

  if (!fs.existsSync(resourcesPath)) {
    console.log("Resources path not found, skipping web copy");
    return;
  }

  // 拷贝 web dist
  const webDist = path.resolve("../../apps/web/dist");
  const webDest = path.join(resourcesPath, "web");

  if (fs.existsSync(webDist)) {
    fs.cpSync(webDist, webDest, { recursive: true });
    console.log(`Copied web dist to ${webDest}`);
  } else {
    console.warn(`Web dist not found at ${webDist}, run 'pnpm --filter @zju-agent/web build' first`);
  }
}
