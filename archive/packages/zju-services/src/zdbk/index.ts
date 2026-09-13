/**
 * 本科教务网 (zdbk.zju.edu.cn) 服务适配器。
 * 登录态由 login-zju 的 ZDBK 维护（走 zdbk.zju.edu.cn/jwglxt/）。
 *
 * 接口与字段解析参照 CeleChron（lib/http/zjuServices/zdbk.dart + lib/model/session.dart），
 * 该实现已在真实 zdbk.zju.edu.cn 部署上验证。考试查询逻辑同时参考 fiz/src-tauri/src/test.rs。
 */

import type { ZDBK } from "login-zju";
import type { Exam, Grade, TimetableEntry, Semester } from "@zju-agent/core";
import { AppError, ErrorCode, mergeTimetableEntries } from "@zju-agent/core";

const BASE = "https://zdbk.zju.edu.cn/jwglxt";

/** 正方 AJAX 端点要求的请求头（缺失 X-Requested-With 常被拒绝） */
function zdbkHeaders(): Record<string, string> {
  return {
    "Content-Type": "application/x-www-form-urlencoded",
    Referer: `${BASE}/xtgl/index_initMenu.html`,
    "X-Requested-With": "XMLHttpRequest",
    Accept: "application/json, text/javascript, */*; q=0.01",
    "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
  };
}

export class ZdbkService {
  constructor(private zdbk: ZDBK) {}

  private reloginPromise: Promise<boolean> | null = null;

  private async relogin(): Promise<boolean> {
    if (this.reloginPromise) {
      return this.reloginPromise;
    }
    this.reloginPromise = (async () => {
      const orig = console.log;
      try {
        console.log = () => {};
        return await this.zdbk.login();
      } finally {
        console.log = orig;
        this.reloginPromise = null;
      }
    })();
    return this.reloginPromise;
  }

  /**
   * 带会话失效自动重登的 ZDBK 请求包装。
   * 正方教务系统在 session 超时（15~30分钟）后会返回 HTTP 901 或 302 重定向到登录页。
   * 检测到超时时自动触发 this.zdbk.login() 刷新 cookie，并重试一次请求。
   */
  private async fetchWithAutoRelogin(
    url: string,
    init?: RequestInit,
  ): Promise<Response> {
    const doFetch = () => this.zdbk.fetch(url, init);
    let res = await doFetch();

    const isSessionExpired = (status: number, text?: string) => {
      if (status === 901 || status === 302 || status === 401 || status === 403) return true;
      if (
        text &&
        (text.includes("login_ssologin") ||
          text.includes("cas/login") ||
          text.includes("统一身份认证") ||
          text.includes("未登录"))
      ) {
        return true;
      }
      return false;
    };

    if (isSessionExpired(res.status)) {
      try {
        await this.relogin();
        res = await doFetch();
      } catch (err) {
        console.warn(
          `[zju-services/zdbk] 会话过期自动重登录失败：${err instanceof Error ? err.message : String(err)}`,
        );
      }
    } else if (res.ok) {
      const clone = res.clone();
      const text = await clone.text();
      const trimmed = text.trim();
      if (
        trimmed.startsWith("<") ||
        trimmed.includes("login_ssologin") ||
        trimmed.includes("cas/login") ||
        trimmed.includes("统一身份认证")
      ) {
        try {
          await this.relogin();
          res = await doFetch();
        } catch (err) {
          console.warn(
            `[zju-services/zdbk] 响应为登录页，自动重登录失败：${err instanceof Error ? err.message : String(err)}`,
          );
        }
      }
    }

    return res;
  }

  /**
   * 考试安排。参照 Fiz test.rs get_tests（form body → 干净 JSON）：
   *   POST /xskscx/kscx_cxXsgrksIndex.html?doType=query&gnmkdm=N509070&layout=default&su={stuId}
   *   body: _search=false&nd=<ts>&queryModel.showCount=5000&...
   * 同时保留 CeleChron 无-body 正则解析作为回退。
   * @param stuId 学号（= ZJU 用户名）
   * @param activeSemesters 活跃学期标识数组，形如 "2024-2025-2"
   */
  async getExams(stuId: string, activeSemesters: string[]): Promise<Exam[]> {
    // 主路径：Fiz 风格的 form body POST，返回干净 JSON
    const url = `${BASE}/xskscx/kscx_cxXsgrksIndex.html?doType=query&gnmkdm=N509070&layout=default&su=${encodeURIComponent(stuId)}`;
    const form = new URLSearchParams({
      _search: "false",
      nd: String(Date.now()),
      "queryModel.showCount": "5000",
      "queryModel.currentPage": "1",
      "queryModel.sortName": "xkkh",
      "queryModel.sortOrder": "desc",
      time: "0",
    });
    const res = await this.fetchWithAutoRelogin(url, {
      method: "POST",
      body: form,
      headers: zdbkHeaders(),
    });
    if (!res.ok) {
      throw new AppError(
        ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
        `教务网考试接口返回 HTTP ${res.status}`,
        { retryable: true },
      );
    }
    const text = await res.text();

    // 解析：优先按干净 JSON（Fiz 路径），失败则回退到容错提取（CeleChron 路径）
    let items: unknown[];
    try {
      const json = JSON.parse(text) as { items?: unknown[] };
      items = json.items ?? [];
    } catch {
      // 回退：CeleChron 风格——容错扫描 "items":[ ... ]（支持嵌套/换行）
      const itemsJson = extractItemsArray(text);
      if (itemsJson) {
        try {
          items = JSON.parse(itemsJson) as unknown[];
        } catch {
          return [];
        }
      } else {
        return [];
      }
    }
    const exams: Exam[] = [];
    for (const item of items) {
      if (!item || typeof item !== "object") continue;
      const r = item as Record<string, unknown>;
      const xkkh = String(r["xkkh"] ?? "");
      // xkkh 形如 "(2024-2025-2)-...-..."；用正则提取学期 id，避免硬编码切片
      const semId = semesterFromXkkh(xkkh);
      if (!semId || !activeSemesters.includes(semId)) continue;
      // 期末：kssj + jsmc + zwxh
      const kssj = r["kssj"];
      if (kssj != null && kssj !== "") {
        exams.push({
          id: `${semId}-${r["kcmc"] ?? ""}-期末`,
          courseName: String(r["kcmc"] ?? ""),
          time: parseExamDateTime(String(kssj)),
          location: strOrUndef(r["jsmc"]),
          seat: strOrUndef(r["zwxh"]),
          semester: semId,
        });
      }
      // 期中：qzkssj + qzjsmc + qzzwxh
      const qzkssj = r["qzkssj"];
      if (qzkssj != null && qzkssj !== "") {
        exams.push({
          id: `${semId}-${r["kcmc"] ?? ""}-期中`,
          courseName: String(r["kcmc"] ?? ""),
          time: parseExamDateTime(String(qzkssj)),
          location: strOrUndef(r["qzjsmc"]),
          seat: strOrUndef(r["qzzwxh"]),
          semester: semId,
        });
      }
    }
    // 去重 + 按时间排序
    const dedup = new Map<string, Exam>();
    for (const e of exams) dedup.set(e.id, e);
    return [...dedup.values()].sort((a, b) =>
      (a.time ?? "").localeCompare(b.time ?? ""),
    );
  }

  /**
   * 课程表。参照 CeleChron getTimetable：
   *   POST /kbcx/xskbcx_cxXsKb.html
   *   body: xnm=<year>&xqm=<season>&captcha_value=
   * CeleChron 对每个合并学期发两次请求（春夏→春+夏，秋冬→秋+冬）再合并，
   * 此处沿用：把 xnxq01id 拆成两个子学期 season 各请求一次，去重合并。
   *
   * @param _stuId 学号（保留参数兼容；正方此接口用 cookie 鉴权，不强制 stuId）
   * @param xnxq01id 学期标识，如 "2024-2025-2"
   */
  async getTimetable(
    _stuId: string,
    xnxq01id: string,
  ): Promise<TimetableEntry[]> {
    const seasons = xnxq01idToSeasons(xnxq01id);
    if (seasons.length === 0) {
      throw new AppError(
        ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
        `无法解析学期标识：${xnxq01id}`,
        { retryable: false },
      );
    }
    const url = `${BASE}/kbcx/xskbcx_cxXsKb.html`;
    const all: TimetableEntry[] = [];
    const seen = new Set<string>();
    for (const { year, season } of seasons) {
      const form = new URLSearchParams({
        xnm: year,
        xqm: season,
        captcha_value: "",
      });
      let res: Response;
      try {
        res = await this.fetchWithAutoRelogin(url, {
          method: "POST",
          body: form,
          headers: zdbkHeaders(),
        });
      } catch (err) {
        throw new AppError(
          ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
          `教务网课表请求失败：${err instanceof Error ? err.message : String(err)}`,
          { retryable: true },
        );
      }
      if (!res.ok) {
        throw new AppError(
          ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
          `教务网课表接口返回 HTTP ${res.status}`,
          { retryable: true },
        );
      }
      const text = await res.text();
      const items = parseKbList(text);
      for (const item of items) {
        const entry = toTimetableEntry(item, xnxq01id);
        if (!entry) continue;
        // 去重：服务端可能在两次请求里返回重叠条目
        const key = `${entry.courseName}|${entry.teacher ?? ""}|${entry.weekday}|${entry.startSection}|${entry.subSemester ?? ""}`;
        if (seen.has(key)) continue;
        seen.add(key);
        all.push(entry);
      }
    }
    return mergeTimetableEntries(all);
  }

  /**
   * 成绩查询。参照 CeleChron getTranscript：
   *   POST /cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000
   *   body 为空（仅 headers + cookie）
   * 响应含全历史成绩，按 xkkh 学期切片过滤。
   * @param _stuId 学号（= ZJU 用户名，未直接用于请求，保留兼容）
   * @param xnxq01id 学期标识，如 "2024-2025-2"；为空时不过滤（返回全部）
   */
  async getGrades(
    _stuId: string,
    xnxq01id: string,
  ): Promise<Grade[]> {
    // ZDBK 成绩接口：空 body，只带 headers
    const url = `${BASE}/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000`;
    const res = await this.fetchWithAutoRelogin(url, {
      method: "POST",
      headers: {
        Referer: `${BASE}/xtgl/index_initMenu.html`,
        "X-Requested-With": "XMLHttpRequest",
        Accept: "application/json, text/javascript, */*; q=0.01",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      },
    });
    if (!res.ok) {
      throw new AppError(ErrorCode.ZJU_RESPONSE_PARSE_FAILED, `成绩接口 HTTP ${res.status}`, { retryable: true });
    }
    const text = await res.text();
    // 容错提取 items（正则失败时不泄露原始响应内容）
    const itemsJson = extractItemsArray(text);
    if (!itemsJson) {
      throw new AppError(
        ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
        "成绩接口响应格式异常，无法提取成绩数据。",
        { retryable: true },
      );
    }
    let items: unknown[];
    try {
      items = JSON.parse(itemsJson) as unknown[];
    } catch {
      throw new AppError(
        ErrorCode.ZJU_RESPONSE_PARSE_FAILED,
        "成绩接口返回数据解析失败。",
        { retryable: true },
      );
    }
    const grades: Grade[] = [];
    for (const item of items) {
      if (!item || typeof item !== "object") continue;
      const r = item as Record<string, unknown>;
      const xkkh = String(r["xkkh"] ?? "");
      if (!xkkh) continue;
      const semId = semesterFromXkkh(xkkh);
      if (!semId) continue;
      if (xnxq01id && semId !== xnxq01id) continue;
      grades.push(toGrade(item, semId));
    }
    return grades;
  }
}

/**
 * 容错提取 `"items":[ ... ]` 数组（支持嵌套对象/字符串/换行）。
 * 逐字符扫描括号配对，规避正则对单行 JSON 的脆弱依赖。
 */
function extractItemsArray(text: string): string | null {
  const key = '"items"';
  const idx = text.indexOf(key);
  if (idx === -1) return null;
  const colon = text.indexOf(":", idx + key.length);
  if (colon === -1) return null;
  let i = colon + 1;
  while (i < text.length && /\s/.test(text[i] ?? "")) i++;
  if (text[i] !== "[") return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (; i < text.length; i++) {
    const ch = text[i] ?? "";
    if (inStr) {
      if (esc) esc = false;
      else if (ch === "\\") esc = true;
      else if (ch === '"') inStr = false;
      continue;
    }
    if (ch === '"') inStr = true;
    else if (ch === "[") depth++;
    else if (ch === "]") {
      depth--;
      if (depth === 0) return text.slice(colon + 1, i + 1);
    }
  }
  return null;
}

/** 从 xkkh 中提取学期 id（如 "(2024-2025-2)-..." → "2024-2025-2"） */
function semesterFromXkkh(xkkh: string): string | undefined {
  return /(\d{4}-\d{4}-[12])/.exec(xkkh)?.[1];
}

/** 解析课表响应。CeleChron 用正则切 kbList；这里直接 JSON.parse（字段名不变） */
function parseKbList(text: string): unknown[] {
  const trimmed = text.trim();
  if (trimmed === "" || trimmed === "null") return [];
  let json: unknown;
  try {
    json = JSON.parse(trimmed);
  } catch {
    return [];
  }
  const kbList = (json as { kbList?: unknown })["kbList"];
  return Array.isArray(kbList) ? (kbList as unknown[]) : [];
}

/** 把正方 kbList 条目转 TimetableEntry。字段对照 CeleChron Session.fromZdbk */
function toTimetableEntry(
  item: unknown,
  semester: string,
): TimetableEntry | null {
  if (!item || typeof item !== "object") return null;
  const r = item as Record<string, unknown>;
  // 研究生课跳过
  if (String(r["sfyjskc"] ?? "") === "1") return null;
  // kcb 是 "课程名<br>?<br>教师<br>地点zwf" 的拼接串，缺失则跳过
  const kcb = r["kcb"];
  if (kcb == null || kcb === "") return null;
  const parsed = parseKcb(String(kcb));
  if (!parsed) return null;

  const weekday = Number(r["xqj"] ?? 0);
  const startSection = Number(r["djj"] ?? 0);
  const duration = Number(r["skcd"] ?? 1);
  const endSection = startSection + (duration > 0 ? duration - 1 : 0);
  const subSemester = strOrUndef(r["xxq"]);

  return {
    id: `${parsed.courseName}-${weekday}-${startSection}`,
    courseName: parsed.courseName,
    teacher: parsed.teacher,
    location: parsed.location,
    weekday: Number.isNaN(weekday) ? 0 : weekday,
    startSection: Number.isNaN(startSection) ? 0 : startSection,
    endSection: Number.isNaN(endSection) ? startSection : endSection,
    weeks: weeksFromDsz(r["dsz"]),
    semester,
    subSemester,
  };
}

/**
 * 解析 kcb 字符串：形如 "课程名<br>中间段<br>教师<br>地点zwf"
 * 参照 CeleChron session.dart:69 的正则 `(.*?)<br>(.*?)<br>(.*?)<br>(.*?)zwf`
 * group(2) 中间段被 CeleChron 丢弃，此处同样不使用。
 */
function parseKcb(kcb: string): {
  courseName: string;
  teacher?: string;
  location?: string;
} | null {
  const m = /(.*?)<br>(.*?)<br>(.*?)<br>(.*?)zwf/.exec(kcb);
  if (!m) return null;
  const courseName = (m[1] ?? "")
    .replaceAll("(", "（")
    .replaceAll(")", "）")
    .trim();
  if (!courseName) return null;
  const teacher = (m[3] ?? "").trim() || undefined;
  const locRaw = (m[4] ?? "").trim();
  const location = locRaw || undefined;
  return { courseName, teacher, location };
}

/**
 * 由 dsz 推导上课周次。
 * CeleChron session.dart:65-66：oddWeek = dsz != '1'，evenWeek = dsz != '0'
 *   dsz='0' → 仅单周(odd)
 *   dsz='1' → 仅双周(even)
 *   其他(含'2') → 单双周都上(每周)
 */
function weeksFromDsz(raw: unknown): number[] {
  const dsz = String(raw ?? "");
  if (dsz === "0") {
    // 单周
    return [1, 3, 5, 7, 9, 11, 13, 15];
  }
  if (dsz === "1") {
    // 双周
    return [2, 4, 6, 8, 10, 12, 14, 16];
  }
  // 每周：留空数组，前端隐藏周次标签
  return [];
}

function strOrUndef(v: unknown): string | undefined {
  if (v == null || v === "") return undefined;
  return String(v);
}

/**
 * 解析教务网考试时间。
 * 格式 1："2026年04月25日(14:00-16:00)" → ISO 8601
 * 格式 2："第N天(HH:MM-HH:MM)"（日历来发布，用占位日期）
 * 参照 CeleChron TimeHelper.parseExamDateTime 与 Fiz test.rs。
 */
function parseExamDateTime(raw: string): string {
  // 格式 1：标准日期 + 时间
  const m = /^(\d{4})年(\d{2})月(\d{2})日\((\d{2}):(\d{2})/.exec(raw);
  if (m) {
    const [, y, mo, d, h, mi] = m;
    return `${y}-${mo}-${d}T${h}:${mi}:00+08:00`;
  }
  // 格式 2："第N天(HH:MM-HH:MM)" — 日历来发布，使用占位日期
  const m2 = /第(\d+)天\((\d{2}):(\d{2})/.exec(raw);
  if (m2) {
    const [, day, h, mi] = m2;
    return `1970-01-${String(day).padStart(2, "0")}T${h}:${mi}:00+08:00`;
  }
  // 无法解析则保留原文
  return raw;
}

/**
 * 把成绩条目转 Grade。
 * 兼容两种来源：zdbk (kcmc/cj/xf/jd/xkkh) 和 ETA (KCMC/CJ/XF/JD/BZ/XN/XQ)
 */
function toGrade(item: unknown, _semester: string): Grade {
  const r = (item && typeof item === "object" ? item : {}) as Record<string, unknown>;
  // ETA 字段优先（大写），fallback 到 zdbk 字段（小写）
  const courseName = String(r["KCMC"] ?? r["kcmc"] ?? "");
  const original = String(r["CJ"] ?? r["cj"] ?? "");
  const fivePoint = Number(r["JD"] ?? r["jd"] ?? 0) || 0;
  const credit = Number(r["XF"] ?? r["xf"] ?? 0) || 0;
  const bz = String(r["BZ"] ?? r["bz"] ?? "");
  const courseId = String(r["KCH"] ?? r["xkkh"] ?? "");
  // 学期从 ETA 的 XN+XQ 拼接，或从 zdbk 的 xkkh 切片
  let semester = _semester;
  if (!semester && r["XN"] && r["XQ"]) {
    semester = `${String(r["XN"])}-${String(r["XQ"])}`;
  }
  const creditIncluded = !["弃修", "待录", "缓考", "无效"].includes(original) && bz !== "弃修";
  const gpaIncluded = creditIncluded && !["合格", "不合格"].includes(original) && !courseId.includes("xtwkc");
  return {
    id: courseId || `${courseName}-${semester}`,
    courseName: courseName.replaceAll("(", "（").replaceAll(")", "）"),
    credit,
    original,
    fivePoint,
    semester,
    gpaIncluded,
    creditIncluded,
  };
}

/**
 * 把学在浙大学期映射为教务网 xnxq01id。
 * 学在浙大学期名形如 "2024-2025春夏" → 教务网 "2024-2025-2"
 * 春/夏/春夏 → 2；秋/冬/秋冬/短 → 1
 */
export function semesterToXnxq01id(name: string): string | null {
  const m = /^(\d{4}-\d{4})(春|夏|春夏|秋|冬|秋冬|短)$/.exec(name);
  if (!m) return null;
  const year = m[1]!;
  const term = m[2]!;
  const id = ["春", "夏", "春夏"].includes(term) ? "2" : "1";
  return `${year}-${id}`;
}

/** 给定学在浙大学期列表，产出教务网所有学期标识集合 */
export function allXnxq01ids(semesters: Semester[]): string[] {
  const ids = new Set<string>();
  for (const s of semesters) {
    const id = semesterToXnxq01id(s.name);
    if (id) ids.add(id);
  }
  return [...ids];
}

/** @deprecated 使用 allXnxq01ids 代替，不再依赖 isActive */
export function activeXnxq01ids(semesters: Semester[]): string[] {
  return allXnxq01ids(semesters);
}

export { getAcademicPeriod, currentXnxq01id } from "@zju-agent/core";
export type { AcademicPeriod } from "@zju-agent/core";

/**
 * 把教务网 xnxq01id 拆成 CeleChron 风格的 (year, season) 请求对。
 * "2024-2025-2"(春夏) → [{2024-2025, 2|春}, {2024-2025, 2|夏}]
 * "2024-2025-1"(秋冬) → [{2024-2025, 1|秋}, {2024-2025, 1|冬}]
 */
export function xnxq01idToSeasons(
  xnxq01id: string,
): Array<{ year: string; season: string }> {
  const m = /^(\d{4}-\d{4})-(1|2)$/.exec(xnxq01id);
  if (!m) return [];
  const year = m[1]!;
  const term = m[2]!;
  if (term === "2") {
    return [
      { year, season: "2|春" },
      { year, season: "2|夏" },
    ];
  }
  return [
    { year, season: "1|秋" },
    { year, season: "1|冬" },
  ];
}
