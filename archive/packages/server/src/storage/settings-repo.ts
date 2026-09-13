/**
 * settings 表 KV 仓储。
 * 非敏感设置走 SQLite；敏感字段（密码/API Key）走 keychain 加密文件，见 credentials.ts。
 */

import type { Database } from "better-sqlite3";

export class SettingsRepo {
  constructor(private db: Database) {}

  get<T>(key: string): T | null {
    const row = this.db
      .prepare("SELECT value FROM settings WHERE key = ?")
      .get(key) as { value: string } | undefined;
    if (!row) return null;
    try {
      return JSON.parse(row.value) as T;
    } catch {
      return row.value as unknown as T;
    }
  }

  set<T>(key: string, value: T): void {
    const now = new Date().toISOString();
    const str = typeof value === "string" ? value : JSON.stringify(value);
    this.db
      .prepare(
        `INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
      )
      .run(key, str, now);
  }

  delete(key: string): void {
    this.db.prepare("DELETE FROM settings WHERE key = ?").run(key);
  }

  keys(): string[] {
    const rows = this.db
      .prepare("SELECT key FROM settings")
      .all() as { key: string }[];
    return rows.map((r) => r.key);
  }
}
