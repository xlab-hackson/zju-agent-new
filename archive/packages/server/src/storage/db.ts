/**
 * SQLite 存储。
 * 使用 better-sqlite3（同步、嵌入式、零外部服务）。
 * 表结构见 ZJU_CAMPUS_AGENT_PROJECT.md 第 12.1 节。
 */

import BetterSqlite3, { type Database } from "better-sqlite3";
import { join } from "node:path";
import { mkdirSync, chmodSync, existsSync } from "node:fs";
import { logger } from "../config/logger.js";

export type Storage = {
  db: Database;
  close(): void;
};

const SCHEMA = `
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT,
  metadata TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id);

CREATE TABLE IF NOT EXISTS campus_cache (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  expires_at TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS downloads (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  status TEXT NOT NULL,
  metadata TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS reminders (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  remind_at TEXT NOT NULL,
  source TEXT,
  metadata TEXT,
  enabled INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  action TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  input_summary TEXT,
  confirmed INTEGER,
  result TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS pending_confirmations (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  tool_name TEXT NOT NULL,
  risk_level TEXT NOT NULL,
  summary TEXT NOT NULL,
  input_preview TEXT,
  input TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
`;

export function initStorage(appDir: string): Storage {
  const dataDir = join(appDir, "data");
  mkdirSync(dataDir, { recursive: true });
  const dbPath = join(dataDir, "agent.db");
  const db = new BetterSqlite3(dbPath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA);
  // 收紧数据库文件权限（含 WAL/SHM），防止会话数据被本机其他用户读取
  for (const f of [dbPath, `${dbPath}-wal`, `${dbPath}-shm`]) {
    if (existsSync(f)) {
      try {
        chmodSync(f, 0o600);
      } catch {
        // 忽略（文件系统不支持时）
      }
    }
  }
  logger.info("SQLite 已初始化", { dbPath });
  return {
    db,
    close() {
      try {
        db.close();
      } catch {
        // ignore
      }
    },
  };
}
