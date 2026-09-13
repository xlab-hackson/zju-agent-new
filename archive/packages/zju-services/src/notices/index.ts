/**
 * 学校通知公告服务 (NoticeService)
 *
 * 抓取「素质拓展平台」与「教务系统·通知公告」两个公开 JSON 接口，
 * 均免登录、无需浙大凭据（2026-09 实测，协议记录参照「浙大网页抓包」项目）。
 *
 * 协议要点（勿随意改动请求形态）：
 * - 素拓：GET .../getTzggList?page=1&limit=N，响应 code!==0 视为失败，
 *   fbsj 为 UTC ISO 时间（如 2026-07-06T07:09:17.000+00:00），须转北京时间取日期；
 *   nr 为正文 HTML；详情在 Vue SPA 弹窗内，无独立 URL，统一拼 hash 路由。
 * - 教务：POST xwck_cxMoreLoginNews.html?doType=query（登录页新闻接口，匿名可用；
 *   登录后的 xwgl_* 接口对程序会话一律返回 901 不可用，见抓包项目 docs/ISSUES.md）。
 *   jqGrid 风格 queryModel.* 表单，X-Requested-With: XMLHttpRequest 必带；
 *   发布人是 xwfbr（fbr 是学号）；sfzd==="1" 表示置顶；fbsj 为本地时间字符串。
 * - 两个源的响应都必须带 Chrome UA，否则可能被拒。
 */

import {
  type Notice,
  type NoticeFetchResult,
  NOTICE_SOURCE_NAMES,
  noticeId,
  AppError,
  ErrorCode,
} from "@zju-agent/core";

const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36";
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_LIMIT = 50;

const SZTZ_API = "https://sztz.zju.edu.cn/dekt/student/home/getTzggList";
const SZTZ_DETAIL_URL = "https://sztz.zju.edu.cn/dekt/#/index/tzgg?id={id}";

const ZDBK_API =
  "https://zdbk.zju.edu.cn/jwglxt/xtgl/xwck_cxMoreLoginNews.html?doType=query";
const ZDBK_DETAIL_URL =
  "https://zdbk.zju.edu.cn/jwglxt/xtgl/xwck_ckLoginNews.html?xwbh={xwbh}";

export class NoticeService {
  /** 素质拓展平台通知公告（免登录） */
  async getSztzNotices(limit = 15): Promise<Notice[]> {
    const n = clampLimit(limit);
    const payload = await this.fetchJson(`${SZTZ_API}?page=1&limit=${n}`, {
      method: "GET",
    });
    return parseSztzResponse(payload, n);
  }

  /** 教务系统通知公告（登录页新闻接口，免登录） */
  async getZdbkNotices(limit = 15): Promise<Notice[]> {
    const n = clampLimit(limit);
    const body = new URLSearchParams({
      xwbt: "",
      "queryModel.showCount": String(n),
      "queryModel.currentPage": "1",
      "queryModel.sortName": "sfzd desc, fbsj",
      "queryModel.sortOrder": "desc",
      time: "0",
    });
    const payload = await this.fetchJson(ZDBK_API, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-Requested-With": "XMLHttpRequest",
      },
      body: body.toString(),
    });
    return parseZdbkResponse(payload, n);
  }

  /**
   * 合并两源最近通知：并发抓取、单源失败不抛出（进 failures）、
   * 按 URL 去重、置顶优先 + 日期倒序。
   */
  async getAllNotices(limitPerSource = 15): Promise<NoticeFetchResult> {
    const results = await Promise.allSettled([
      this.getSztzNotices(limitPerSource),
      this.getZdbkNotices(limitPerSource),
    ]);

    const items: Notice[] = [];
    const failures: string[] = [];
    const seen = new Set<string>();
    const collect = (r: PromiseSettledResult<Notice[]>) => {
      if (r.status === "fulfilled") {
        for (const n of r.value) {
          if (seen.has(n.url)) continue;
          seen.add(n.url);
          items.push(n);
        }
      } else {
        const reason = r.reason;
        failures.push(
          reason instanceof AppError
            ? reason.message
            : "网络请求失败，请稍后重试。",
        );
      }
    };
    collect(results[0]!);
    collect(results[1]!);

    items.sort((a, b) => {
      if (!!a.important !== !!b.important) return a.important ? -1 : 1;
      return (b.date || "0").localeCompare(a.date || "0");
    });
    return { items, failures };
  }

  private async fetchJson(url: string, init: RequestInit): Promise<unknown> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    let res: Response;
    try {
      res = await fetch(url, {
        ...init,
        headers: { "User-Agent": USER_AGENT, ...(init.headers ?? {}) },
        signal: controller.signal,
      });
    } catch {
      throw new AppError(
        ErrorCode.ZJU_SERVICE_UNAVAILABLE,
        "学校通知源暂时无法访问，请检查网络后重试。",
        { retryable: true },
      );
    } finally {
      clearTimeout(timer);
    }
    if (!res.ok) {
      throw new AppError(
        ErrorCode.ZJU_SERVICE_UNAVAILABLE,
        `学校通知源响应异常（HTTP ${res.status}）。`,
        { retryable: true },
      );
    }
    try {
      return (await res.json()) as unknown;
    } catch {
      throw new AppError(
        ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
        "学校通知源返回了无法解析的数据（可能已改版）。",
        { retryable: true },
      );
    }
  }
}

// ---------- 纯解析函数（可单测，样本来自抓包项目 tests/fixtures） ----------

type SztzRecord = {
  id?: number | string;
  mc?: string;
  fbsj?: string;
  fbr?: string;
  nr?: string;
};

/** 素拓 getTzggList 响应 → Notice[]（code!==0 抛错，字段映射见文件头注释） */
export function parseSztzResponse(payload: unknown, limit = 15): Notice[] {
  const code = (payload as { code?: unknown }).code;
  if (code !== undefined && code !== 0) {
    throw new AppError(
      ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
      "素质拓展平台接口返回异常。",
      { retryable: true },
    );
  }
  const data = extractRecords(payload, ["data"]);
  if (data.length === 0) return [];
  const out: Notice[] = [];
  const seen = new Set<string>();
  for (const rec of data) {
    if (out.length >= clampLimit(limit)) break;
    if (typeof rec !== "object" || rec === null) continue;
    const r = rec as SztzRecord;
    const title = (r.mc ?? "").trim();
    const rawId = r.id === undefined || r.id === null ? "" : String(r.id);
    if (!title || !rawId) continue;
    const url = SZTZ_DETAIL_URL.replace("{id}", encodeURIComponent(rawId));
    if (seen.has(url)) continue;
    seen.add(url);
    out.push({
      id: noticeId(url),
      source: "sztz",
      sourceName: NOTICE_SOURCE_NAMES.sztz,
      title,
      url,
      date: toBeijingDate(r.fbsj ?? ""),
      publisher: (r.fbr ?? "").trim() || undefined,
      summary: htmlToText(r.nr ?? "") || undefined,
    });
  }
  return out;
}

type ZdbkRecord = {
  xwbh?: string;
  xwbt?: string;
  fbsj?: string;
  xwfbr?: string;
  sfzd?: string;
};

/** 教务 xwck_cxMoreLoginNews 响应 → Notice[] */
export function parseZdbkResponse(payload: unknown, limit = 15): Notice[] {
  const data = extractRecords(payload, ["items"]);
  const out: Notice[] = [];
  const seen = new Set<string>();
  for (const rec of data) {
    if (out.length >= clampLimit(limit)) break;
    if (typeof rec !== "object" || rec === null) continue;
    const r = rec as ZdbkRecord;
    const title = (r.xwbt ?? "").trim();
    const xwbh = (r.xwbh ?? "").trim();
    if (!title || !xwbh) continue;
    const url = ZDBK_DETAIL_URL.replace("{xwbh}", encodeURIComponent(xwbh));
    if (seen.has(url)) continue;
    seen.add(url);
    out.push({
      id: noticeId(url),
      source: "zdbk",
      sourceName: NOTICE_SOURCE_NAMES.zdbk,
      title,
      url,
      date: normalizeDate(r.fbsj ?? ""),
      publisher: (r.xwfbr ?? "").trim() || undefined,
      important: r.sfzd === "1" ? true : undefined,
    });
  }
  return out;
}

/** 按点分路径从嵌套对象中提取记录数组，取不到返回 [] */
function extractRecords(payload: unknown, path: string[]): unknown[] {
  let cur: unknown = payload;
  for (const key of path) {
    if (typeof cur === "object" && cur !== null && key in cur) {
      cur = (cur as Record<string, unknown>)[key];
    } else {
      return [];
    }
  }
  return Array.isArray(cur) ? cur : [];
}

/** HTML → 纯文本摘要（剥标签 + 实体 + 压缩空白） */
export function htmlToText(html: string, maxLen = 200): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLen);
}

/**
 * 素拓 fbsj（UTC ISO，如 "2026-07-06T07:09:17.000+00:00"）→ 北京时间 "YYYY-MM-DD"。
 * 无时区后缀的值按北京时间理解。解析失败返回 ""。
 */
export function toBeijingDate(raw: string): string {
  if (!raw) return "";
  const hasTz = /(?:Z|[+-]\d{2}:?\d{2})$/i.test(raw);
  const dt = new Date(hasTz ? raw : `${raw}+08:00`);
  if (Number.isNaN(dt.getTime())) return "";
  return new Date(dt.getTime() + 8 * 3_600_000).toISOString().slice(0, 10);
}

/** 教务 fbsj（"2026-09-03 17:06:22"）→ 取前 10 位日期；格式不符返回 "" */
export function normalizeDate(raw: string): string {
  const m = /^(\d{4}-\d{2}-\d{2})/.exec(raw ?? "");
  return m ? m[1]! : "";
}

function clampLimit(limit: number): number {
  if (!Number.isFinite(limit) || limit <= 0) return 15;
  return Math.min(Math.floor(limit), MAX_LIMIT);
}
