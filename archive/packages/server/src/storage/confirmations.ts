/**
 * Pending confirmation 仓储。
 * 高风险工具调用在执行前落库一条待确认记录，用户确认后才继续执行。
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 9.4 节。
 */

import type { Database } from "better-sqlite3";
import { nanoid } from "nanoid";
import type {
  PendingConfirmation,
  ToolRiskLevel,
  ToolCall,
} from "@zju-agent/core";

const TTL_MS = 5 * 60_000; // 待确认 5 分钟过期

export type StoredConfirmation = PendingConfirmation & {
  /** 触发该确认的原始 toolCall（确认后由 Agent loop 重放执行） */
  toolCall: ToolCall;
};

export class ConfirmationRepo {
  constructor(private db: Database) {}

  create(input: {
    conversationId: string;
    toolCall: ToolCall;
    riskLevel: ToolRiskLevel;
    summary: string;
    inputPreview: unknown;
  }): StoredConfirmation {
    const id = nanoid();
    const now = new Date();
    const expiresAt = new Date(now.getTime() + TTL_MS).toISOString();
    const record: StoredConfirmation = {
      id,
      conversationId: input.conversationId,
      toolName: input.toolCall.name,
      riskLevel: input.riskLevel,
      summary: input.summary,
      inputPreview: input.inputPreview,
      input: input.toolCall.input,
      expiresAt,
      toolCall: input.toolCall,
    };
    this.db
      .prepare(
        `INSERT INTO pending_confirmations
         (id, conversation_id, tool_name, risk_level, summary, input_preview, input, expires_at, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        id,
        input.conversationId,
        record.toolName,
        input.riskLevel,
        input.summary,
        JSON.stringify(input.inputPreview),
        JSON.stringify(input.toolCall),
        expiresAt,
        now.toISOString(),
      );
    return record;
  }

  get(id: string): StoredConfirmation | null {
    // 惰性清理过期记录，保证 TTL 真正生效
    this.purgeExpired();
    const row = this.db
      .prepare("SELECT * FROM pending_confirmations WHERE id = ?")
      .get(id) as PendingRow | undefined;
    if (!row) return null;
    const rec = this.hydrate(row);
    if (isExpired(rec)) {
      this.delete(id);
      return null;
    }
    return rec;
  }

  /**
   * 原子认领：同一同步块内读取并删除，确保并发确认时只有一个调用者拿到记录，
   * 避免工具被重复执行。
   */
  claim(id: string): StoredConfirmation | null {
    const row = this.db
      .prepare("SELECT * FROM pending_confirmations WHERE id = ?")
      .get(id) as PendingRow | undefined;
    if (!row) return null;
    this.delete(id);
    const rec = this.hydrate(row);
    if (isExpired(rec)) return null;
    return rec;
  }

  delete(id: string): void {
    this.db.prepare("DELETE FROM pending_confirmations WHERE id = ?").run(id);
  }

  /** 清理已过期记录 */
  purgeExpired(): number {
    const now = new Date().toISOString();
    const r = this.db
      .prepare("DELETE FROM pending_confirmations WHERE expires_at < ?")
      .run(now);
    return r.changes;
  }

  private hydrate(row: PendingRow): StoredConfirmation {
    const inputPreview = safeParse(row.input_preview);
    const toolCall = safeParse(row.input) as ToolCall;
    return {
      id: row.id,
      conversationId: row.conversation_id,
      toolName: row.tool_name,
      riskLevel: row.risk_level as ToolRiskLevel,
      summary: row.summary,
      inputPreview,
      input: toolCall.input,
      expiresAt: row.expires_at,
      toolCall,
    };
  }
}

type PendingRow = {
  id: string;
  conversation_id: string;
  tool_name: string;
  risk_level: string;
  summary: string;
  input_preview: string;
  input: string;
  expires_at: string;
  created_at: string;
};

function safeParse(s: string | null): unknown {
  if (!s) return null;
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

function isExpired(rec: StoredConfirmation): boolean {
  if (!rec.expiresAt) return false;
  const ts = Date.parse(rec.expiresAt);
  return !Number.isNaN(ts) && ts < Date.now();
}
