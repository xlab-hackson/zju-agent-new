import { z } from "zod";

/**
 * 统一 API 响应结构。
 * 后端所有接口返回 { ok: true, data } 或 { ok: false, error }。
 */
export type ApiResponse<T> =
  | { ok: true; data: T }
  | { ok: false; error: ApiError };

export const apiErrorSchema = z.object({
  code: z.string(),
  message: z.string(),
  detail: z.unknown().optional(),
  retryable: z.boolean().optional(),
});

export type ApiError = z.infer<typeof apiErrorSchema>;

/** 构造成功响应 */
export function ok<T>(data: T): ApiResponse<T> {
  return { ok: true, data };
}

/** 构造失败响应 */
export function fail(
  code: string,
  message: string,
  opts?: { detail?: unknown; retryable?: boolean },
): ApiResponse<never> {
  return {
    ok: false,
    error: {
      code,
      message,
      detail: opts?.detail,
      retryable: opts?.retryable,
    },
  };
}

/** 未捕获异常的日志槽：由宿主（server）注入，避免 core 依赖具体 logger */
let unknownErrorSink: ((err: unknown) => void) | null = null;

/** 设置未捕获异常的日志回调（服务端启动时调用一次） */
export function setUnknownErrorSink(fn: ((err: unknown) => void) | null): void {
  unknownErrorSink = fn;
}

/** 包装异步处理函数为 ApiResponse，自动捕获抛出的 AppError */
export async function wrap<T>(
  fn: () => Promise<T>,
): Promise<ApiResponse<T>> {
  try {
    return ok(await fn());
  } catch (err) {
    if (err instanceof AppError) {
      return fail(err.code, err.message, {
        detail: err.detail,
        retryable: err.retryable,
      });
    }
    // 内部错误：原始消息只进服务端日志，不下发客户端（避免泄露内部实现细节）
    unknownErrorSink?.(err);
    return fail("UNKNOWN_ERROR", "服务器内部错误，请查看服务端日志。", {
      retryable: false,
    });
  }
}

/**
 * 应用层错误。抛出后由 wrap() 转换为 ApiResponse。
 * 携带错误码、可重试标志、脱敏后的 detail。
 */
export class AppError extends Error {
  readonly code: string;
  readonly detail?: unknown;
  readonly retryable: boolean;

  constructor(
    code: string,
    message: string,
    opts?: { detail?: unknown; retryable?: boolean; cause?: unknown },
  ) {
    super(message, { cause: opts?.cause });
    this.name = "AppError";
    this.code = code;
    this.detail = opts?.detail;
    this.retryable = opts?.retryable ?? false;
  }
}
