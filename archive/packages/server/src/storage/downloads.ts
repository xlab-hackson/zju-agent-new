/**
 * 下载记录仓储。
 * 文件实体落盘到 config.downloadDir，元数据记录在 downloads 表。
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 10.4 节。
 */

import type { Database } from "better-sqlite3";
import { nanoid } from "nanoid";

export type DownloadSource = "courses" | "classroom";

export type DownloadRecord = {
  id: string;
  source: DownloadSource;
  fileName: string;
  /** 绝对路径，仅本地展示 */
  filePath: string;
  status: "completed" | "failed";
  size: number;
  mimeType?: string;
  courseId?: string;
  materialId?: string;
  fileId?: string;
  createdAt: string;
  updatedAt: string;
};

export type CreateDownloadInput = {
  source: DownloadSource;
  fileName: string;
  filePath: string;
  status: "completed" | "failed";
  size: number;
  mimeType?: string;
  courseId?: string;
  materialId?: string;
  fileId?: string;
};

export class DownloadsRepo {
  constructor(private db: Database) {}

  create(input: CreateDownloadInput): DownloadRecord {
    const id = nanoid();
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO downloads
         (id, source, file_name, file_path, status, metadata, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        id,
        input.source,
        input.fileName,
        input.filePath,
        input.status,
        JSON.stringify({
          size: input.size,
          mimeType: input.mimeType,
          courseId: input.courseId,
          materialId: input.materialId,
          fileId: input.fileId,
        }),
        now,
        now,
      );
    return this.toRecord({
      id,
      source: input.source,
      file_name: input.fileName,
      file_path: input.filePath,
      status: input.status,
      metadata: JSON.stringify({
        size: input.size,
        mimeType: input.mimeType,
        courseId: input.courseId,
        materialId: input.materialId,
        fileId: input.fileId,
      }),
      created_at: now,
      updated_at: now,
    });
  }

  list(): DownloadRecord[] {
    const rows = this.db
      .prepare(
        "SELECT * FROM downloads ORDER BY created_at DESC",
      )
      .all() as DownloadRow[];
    return rows.map((r) => this.toRecord(r));
  }

  get(id: string): DownloadRecord | null {
    const row = this.db
      .prepare("SELECT * FROM downloads WHERE id = ?")
      .get(id) as DownloadRow | undefined;
    return row ? this.toRecord(row) : null;
  }

  delete(id: string): DownloadRecord | null {
    const row = this.get(id);
    if (!row) return null;
    this.db.prepare("DELETE FROM downloads WHERE id = ?").run(id);
    return row;
  }

  clear(): void {
    this.db.prepare("DELETE FROM downloads").run();
  }

  private toRecord(row: DownloadRow): DownloadRecord {
    let meta: {
      size?: number;
      mimeType?: string;
      courseId?: string;
      materialId?: string;
      fileId?: string;
    } = {};
    try {
      meta = JSON.parse(row.metadata ?? "{}");
    } catch {
      meta = {};
    }
    return {
      id: row.id,
      source: row.source as DownloadSource,
      fileName: row.file_name,
      filePath: row.file_path,
      status: row.status as "completed" | "failed",
      size: meta.size ?? 0,
      mimeType: meta.mimeType,
      courseId: meta.courseId,
      materialId: meta.materialId,
      fileId: meta.fileId,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }
}

type DownloadRow = {
  id: string;
  source: string;
  file_name: string;
  file_path: string;
  status: string;
  metadata: string | null;
  created_at: string;
  updated_at: string;
};
