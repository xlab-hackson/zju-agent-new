/**
 * 极简内存限流器（本地单进程应用足够）：
 * 按 key（如 IP）滑动窗口计数，超出阈值返回 false。
 */

type Bucket = { count: number; resetAt: number };

export function createRateLimiter(opts: {
  windowMs: number;
  max: number;
}): { check(key: string): boolean } {
  const buckets = new Map<string, Bucket>();
  return {
    check(key: string): boolean {
      const now = Date.now();
      // 顺带清理过期桶，避免长生命周期进程下 Map 无限增长
      for (const [k, b] of buckets) {
        if (b.resetAt <= now) buckets.delete(k);
      }
      const b = buckets.get(key);
      if (!b || b.resetAt <= now) {
        buckets.set(key, { count: 1, resetAt: now + opts.windowMs });
        return true;
      }
      b.count += 1;
      if (b.count > opts.max) return false;
      return true;
    },
  };
}
