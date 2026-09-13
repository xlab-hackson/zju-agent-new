/**
 * 下载落盘工具。
 *
 * 安全约定：
 * - 仅写到 config.downloadDir 内，禁止相对路径越界（.. / 绝对路径）。
 * - 同名文件默认追加序号，不覆盖既有文件（见 ZJU_CAMPUS_AGENT_PROJECT.md 安全约定）。
 * - 校验文件存在性与大小，空文件视为失败。
 */

import { createWriteStream, mkdirSync, existsSync, statSync } from "node:fs";
import { join, extname, basename } from "node:path";
import { Readable } from "node:stream";
import { randomBytes } from "node:crypto";
import { AppError, ErrorCode } from "@zju-agent/core";

export type WriteStreamInput = {
  /** 返回待写入的流（延迟获取，便于失败重试） */
  stream: () => Promise<ReadableStream<Uint8Array> | NodeJS.ReadableStream>;
  downloadDir: string;
  subdir?: string;
  fileName: string;
};

export type WriteStreamResult = {
  fileName: string;
  filePath: string;
  size: number;
  contentType?: string;
};

export async function writeDownloadStream(
  input: WriteStreamInput,
): Promise<WriteStreamResult> {
  const safeName = secureName(input.fileName);
  const targetDir = resolveTargetDir(input.downloadDir, input.subdir);
  const targetPath = resolveUniquePath(targetDir, safeName);

  const body = await input.stream();
  if (!body) {
    throw new AppError(ErrorCode.FILE_DOWNLOAD_FAILED, "文件流为空。");
  }

  await pumpToDisk(body, targetPath);

  if (!existsSync(targetPath)) {
    throw new AppError(ErrorCode.FILE_DOWNLOAD_FAILED, "文件写入失败。");
  }
  const stat = statSync(targetPath);
  if (stat.size === 0) {
    throw new AppError(ErrorCode.FILE_DOWNLOAD_FAILED, "下载文件为空。");
  }
  return {
    fileName: basename(targetPath),
    filePath: targetPath,
    size: stat.size,
  };
}

/** 将 Web ReadableStream 或 Node 流写入磁盘 */
async function pumpToDisk(
  body: ReadableStream<Uint8Array> | NodeJS.ReadableStream,
  target: string,
): Promise<void> {
  const nodeStream =
    body instanceof ReadableStream ? Readable.fromWeb(body as never) : body;
  await new Promise<void>((resolve, reject) => {
    const ws = createWriteStream(target);
    nodeStream.pipe(ws);
    nodeStream.on("error", reject);
    ws.on("error", reject);
    ws.on("finish", () => resolve());
  });
}

function resolveTargetDir(downloadDir: string, subdir?: string): string {
  if (!subdir) return downloadDir;
  // 禁止 .. 越界
  const clean = subdir.replace(/\.\./g, "").replace(/^[/\\]+/, "");
  const dir = join(downloadDir, clean);
  if (!dir.startsWith(downloadDir)) {
    return downloadDir;
  }
  mkdirSync(dir, { recursive: true });
  return dir;
}

function resolveUniquePath(dir: string, name: string): string {
  let candidate = join(dir, name);
  if (!existsSync(candidate)) return candidate;
  const ext = extname(name);
  const stem = basename(name, ext);
  for (let i = 1; i < 1000; i++) {
    candidate = join(dir, `${stem} (${i})${ext}`);
    if (!existsSync(candidate)) return candidate;
  }
  // 兜底：随机后缀
  return join(dir, `${stem}.${randomBytes(4).toString("hex")}${ext}`);
}

function secureName(name: string): string {
  const base = basename(name).replace(/[<>:"|?*]/g, "_").trim();
  return base.slice(0, 200) || `file-${Date.now()}`;
}
