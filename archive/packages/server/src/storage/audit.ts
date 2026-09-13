/**
 * 审计日志仓储。
 * 所有高风险操作必须记录。
 */

import type { Database } from "better-sqlite3";
import { nanoid } from "nanoid";

export type AuditAction =
  | "tool.execute"
  | "tool.confirm.requested"
  | "tool.confirm.approved"
  | "tool.confirm.rejected"
  | "assignment.submit"
  | "network.recharge"
  | "download";

export class AuditRepo {
  constructor(private db: Database) {}

  log(input: {
    action: AuditAction;
    riskLevel: string;
    inputSummary?: string;
    confirmed?: boolean;
    result?: string;
  }): void {
    const id = nanoid();
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO audit_logs (id, action, risk_level, input_summary, confirmed, result, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        id,
        input.action,
        input.riskLevel,
        input.inputSummary ?? null,
        input.confirmed === undefined ? null : input.confirmed ? 1 : 0,
        input.result ?? null,
        now,
      );
  }
}
