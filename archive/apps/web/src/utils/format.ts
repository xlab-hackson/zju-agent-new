/**
 * 前端通用格式化与小工具。
 */

/**
 * 解析考试时间戳。支持两种格式：
 * - ISO 8601: "2026-04-25T14:00:00+08:00"
 * - 教务网中文: "2026年04月25日(14:00-16:00)" 或 "第N天(HH:MM-HH:MM)"
 * 返回毫秒时间戳，解析失败返回 NaN。
 */
export function parseExamTimestamp(input?: string): number {
  if (!input) return NaN;
  // ISO 8601
  const t = Date.parse(input);
  if (!Number.isNaN(t)) return t;
  // 教务网中文: "2026年04月25日(14:00-16:00)"
  const m = /^(\d{4})年(\d{2})月(\d{2})日\((\d{2}):(\d{2})/.exec(input);
  if (m) {
    const [, y, mo, d, h, mi] = m;
    return Date.parse(`${y}-${mo}-${d}T${h}:${mi}:00+08:00`);
  }
  // "第N天(HH:MM-HH:MM)" — 无具体日期，放在很远的未来
  const m2 = /第(\d+)天\((\d{2}):(\d{2})/.exec(input);
  if (m2) return NaN;
  return NaN;
}

/** RFC3339 或中文考试时间 → "YYYY-MM-DD HH:mm"，失败回退原值 */
export function formatDateTime(input?: string): string {
  if (!input) return "—";
  const t = parseExamTimestamp(input);
  if (Number.isNaN(t)) return input;
  const d = new Date(t);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** 截止时间相对紧迫度 */
export function deadlineUrgency(deadline?: string): "overdue" | "urgent" | "soon" | "normal" | "none" {
  if (!deadline) return "none";
  const t = Date.parse(deadline);
  if (Number.isNaN(t)) return "none";
  const diff = t - Date.now();
  if (diff < 0) return "overdue";
  if (diff < 24 * 3600_000) return "urgent";
  if (diff < 3 * 24 * 3600_000) return "soon";
  return "normal";
}

/** 字节 → 人类可读 */
export function formatBytes(bytes?: number): string {
  if (!bytes || bytes <= 0) return "—";
  const units = ["B", "KB", "MB", "GB"];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(i === 0 ? 0 : 1)} ${units[i]}`;
}

const URGENCY_STYLE: Record<string, string> = {
  overdue: "text-rose-600 font-semibold",
  urgent: "text-rose-500",
  soon: "text-amber-600",
  normal: "text-slate-500",
  none: "text-slate-400",
};

export function urgencyClass(level: ReturnType<typeof deadlineUrgency>): string {
  return URGENCY_STYLE[level] ?? "text-slate-500";
}
