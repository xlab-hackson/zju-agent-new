/**
 * 校园数据缓存仓储。
 * 缓存策略见 ZJU_CAMPUS_AGENT_PROJECT.md 第 12.2 节。
 */

import type { Database } from "better-sqlite3";

const DEFAULT_TTL_MS = {
  courses: 30 * 60_000,
  assignments: 10 * 60_000,
  materials: 30 * 60_000,
  exams: 60 * 60_000,
  timetable: 24 * 60 * 60_000,
} as const;

export type CacheKey = keyof typeof DEFAULT_TTL_MS | string;

export class CampusCache {
  constructor(private db: Database) {}

  /** 读取缓存，未命中或过期返回 null */
  get<T>(key: CacheKey): T | null {
    const row = this.db
      .prepare("SELECT value, expires_at FROM campus_cache WHERE key = ?")
      .get(key) as { value: string; expires_at: string | null } | undefined;
    if (!row) return null;
    if (row.expires_at) {
      const expires = Date.parse(row.expires_at);
      if (Number.isNaN(expires) || expires < Date.now()) {
        return null;
      }
    }
    try {
      return JSON.parse(row.value) as T;
    } catch {
      return null;
    }
  }

  set<T>(key: CacheKey, value: T, ttlMs?: number): void {
    const now = new Date().toISOString();
    const ttl = ttlMs ?? defaultTtl(key);
    const expiresAt = new Date(Date.now() + ttl).toISOString();
    const str = JSON.stringify(value);
    this.db
      .prepare(
        `INSERT INTO campus_cache (key, value, expires_at, updated_at) VALUES (?, ?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, expires_at = excluded.expires_at, updated_at = excluded.updated_at`,
      )
      .run(key, str, expiresAt, now);
  }

  invalidate(key: CacheKey): void {
    this.db.prepare("DELETE FROM campus_cache WHERE key = ?").run(key);
  }

  clear(): void {
    this.db.prepare("DELETE FROM campus_cache").run();
  }
}

function defaultTtl(key: CacheKey): number {
  if (key in DEFAULT_TTL_MS) {
    return DEFAULT_TTL_MS[key as keyof typeof DEFAULT_TTL_MS];
  }
  return 30 * 60_000;
}
