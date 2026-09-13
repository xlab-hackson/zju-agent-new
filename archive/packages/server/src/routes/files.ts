/**
 * 文件与下载路由。
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 10.4 节。
 *
 * 路由：
 *   GET    /api/files/downloads        — 列出下载记录
 *   GET    /api/files/downloads/:id/preview?inline=1  — 读取文件内容（预览/下载）
 *   DELETE /api/files/downloads/:id    — 删除记录（可选删文件）
 *   DELETE /api/files/downloads         — 清空记录
 *
 * 「打开下载目录」属 Electron 能力，纯 Web 阶段仅返回路径。
 */

import type { FastifyPluginAsync } from "fastify";
import { ok, wrap, AppError, ErrorCode } from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";
import { logger } from "../config/logger.js";
import { resolve, sep } from "node:path";
import {
  createReadStream,
  statSync,
  existsSync,
  realpathSync,
  unlinkSync,
} from "node:fs";

export function filesRoutes(
  deps: ServicesContainer & { config: ServerConfig },
): FastifyPluginAsync {
  return async (app) => {
    app.get("/downloads", async () => {
      const records = deps.downloads.list();
      return ok({
        downloadDir: deps.config.downloadDir,
        records,
      });
    });

    // 读取/下载已下载的文件内容。inline=1 走内联预览，否则 attachment 下载。
    app.get<{
      Params: { id: string };
      Querystring: { inline?: string };
    }>("/downloads/:id/preview", async (req, reply) => {
      return wrap(async () => {
        const record = deps.downloads.get(req.params.id);
        if (!record) {
          throw new AppError(ErrorCode.FILE_NOT_FOUND, "下载记录不存在。");
        }
        // 路径安全：必须在下载目录内（含符号链接解析），防越界
        if (!isWithin(deps.config.downloadDir, record.filePath)) {
          throw new AppError(ErrorCode.FILE_NOT_FOUND, "文件路径非法。");
        }
        const target = resolve(record.filePath);
        if (!existsSync(target)) {
          throw new AppError(
            ErrorCode.FILE_NOT_FOUND,
            "文件已被移除或删除。",
          );
        }
        const stat = statSync(target);
        const mime = record.mimeType || guessMime(record.fileName);
        const inline = req.query.inline === "1";
        reply.header("Content-Type", mime);
        reply.header(
          "Content-Disposition",
          `${inline ? "inline" : "attachment"}; filename="${encodeURIComponent(record.fileName)}"`,
        );
        reply.header("Content-Length", String(stat.size));
        reply.header("Cache-Control", "no-store");
        logger.info("读取下载文件", { id: record.id, fileName: record.fileName, inline });
        reply.send(createReadStream(target));
        return;
      });
    });

    app.delete<{ Params: { id: string }; Querystring: { purge?: string } }>(
      "/downloads/:id",
      async (req) => {
        return wrap(async () => {
          const removed = deps.downloads.delete(req.params.id);
          if (!removed) {
            throw new AppError(ErrorCode.FILE_NOT_FOUND, "下载记录不存在。");
          }
          // purge=1 同时删除文件本体（同样做目录约束，防越界删除）
          if (req.query.purge === "1") {
            try {
              if (
                isWithin(deps.config.downloadDir, removed.filePath) &&
                existsSync(removed.filePath)
              ) {
                unlinkSync(removed.filePath);
              } else {
                logger.warn("拒绝删除下载目录外的文件", {
                  filePath: removed.filePath,
                });
              }
            } catch (err) {
              logger.warn("删除文件本体失败", {
                filePath: removed.filePath,
                message: err instanceof Error ? err.message : String(err),
              });
            }
          }
          return { id: removed.id };
        });
      },
    );

    app.delete("/downloads", async () => {
      deps.downloads.clear();
      return ok({ ok: true });
    });
  };
}

/**
 * 目录约束校验：target 必须位于 baseDir 内。
 * 优先解析真实路径（realpath），符号链接指向目录外时判定非法。
 */
function isWithin(baseDir: string, target: string): boolean {
  const base = resolve(baseDir);
  const t = resolve(target);
  if (t === base) return true;
  if (!t.startsWith(base + sep)) return false;
  try {
    const rb = realpathSync(base);
    const rt = realpathSync(t);
    if (rt === rb) return true;
    return rt.startsWith(rb + sep);
  } catch {
    // 目标不存在（realpath 失败）时，字符串前缀校验已通过，后续 existsSync 会拦截
    return true;
  }
}

function guessMime(fileName: string): string {
  const ext = fileName.toLowerCase().split(".").pop() ?? "";
  const map: Record<string, string> = {
    pdf: "application/pdf",
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    webp: "image/webp",
    svg: "image/svg+xml",
    txt: "text/plain",
    md: "text/markdown",
    json: "application/json",
    mp4: "video/mp4",
    mp3: "audio/mpeg",
    docx: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    doc: "application/msword",
    pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ppt: "application/vnd.ms-powerpoint",
    xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    xls: "application/vnd.ms-excel",
    zip: "application/zip",
  };
  return map[ext] ?? "application/octet-stream";
}

