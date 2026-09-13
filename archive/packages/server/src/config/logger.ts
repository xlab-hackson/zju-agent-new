/**
 * 简易日志器。
 * 安全要求：日志中不得出现密码、cookie、API Key。
 * 提供专门的 redact 工具，用于在记录 detail 前脱敏。
 */

type Level = "debug" | "info" | "warn" | "error";

function format(level: Level, msg: string, meta?: unknown): string {
  const ts = new Date().toISOString();
  const metaStr =
    meta === undefined
      ? ""
      : typeof meta === "string"
        ? ` ${meta}`
        : ` ${safeStringify(meta)}`;
  return `[${ts}] ${level.toUpperCase()} ${msg}${metaStr}`;
}

function safeStringify(obj: unknown): string {
  try {
    return JSON.stringify(redact(obj));
  } catch {
    return String(obj);
  }
}

/** 脱敏：递归移除敏感字段 */
export function redact<T>(input: T): T {
  if (input === null || typeof input !== "object") return input;
  if (Array.isArray(input)) return input.map(redact) as unknown as T;
  const SENSITIVE = new Set([
    "password",
    "passwd",
    "apiKey",
    "api_key",
    "apikey",
    "token",
    "accessToken",
    "access_token",
    "cookie",
    "set-cookie",
    "authorization",
    "secret",
  ]);
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(input as Record<string, unknown>)) {
    if (SENSITIVE.has(k)) {
      out[k] = typeof v === "string" ? mask(v) : "***";
    } else if (typeof v === "object" && v !== null) {
      out[k] = redact(v);
    } else {
      out[k] = v;
    }
  }
  return out as T;
}

function mask(s: string): string {
  if (s.length <= 6) return "***";
  return s.slice(0, 3) + "***" + s.slice(-2);
}

export const logger = {
  debug(msg: string, meta?: unknown) {
    if (process.env.NODE_ENV !== "production") {
      console.debug(format("debug", msg, meta));
    }
  },
  info(msg: string, meta?: unknown) {
    console.log(format("info", msg, meta));
  },
  warn(msg: string, meta?: unknown) {
    console.warn(format("warn", msg, meta));
  },
  error(msg: string, meta?: unknown) {
    console.error(format("error", msg, meta));
  },
};
