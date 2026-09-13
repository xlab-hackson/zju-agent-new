/**
 * 浙大校历服务 (CalendarService)
 * 借鉴 Celechron 校历与节假日调休体系重构。
 *
 * 核心目标：
 * 1. 彻底切断对「学在浙大」接口推断学期的依赖；
 * 2. 具备离线回退能力（内置校历配置），网络可用时自动从 calendar.celechron.top 增量更新；
 * 3. 向全系统提供权威学期判定、当前教学周计算、节假日与调休判定、每日/每周日程投影。
 */

import {
  type SemesterCalendarConfig,
  type AcademicDateInfo,
  type DailySchedule,
  type UpcomingSchedule48h,
  type TimetableEntry,
  type Exam,
  type Assignment,
  ZJU_STANDARD_SESSION_TIMES,
  getAcademicSemesterId,
  calculateAcademicDateInfo,
  buildDailySchedule,
  buildUpcomingSchedule48h,
} from "@zju-agent/core";

const BUNDLED_CALENDARS: Record<string, SemesterCalendarConfig> = {
  "2026-2027-1": {
    semesterId: "2026-2027-1",
    name: "2026-2027学年秋冬学期",
    sessionTimes: ZJU_STANDARD_SESSION_TIMES,
    startEnd: ["20260914", "20261108", "20261109", "20270103"],
    holiday: {
      "20260925": "中秋节",
      "20261001": "国庆节",
      "20261005": "国庆节",
    },
    dummy: {
      "20260927": "中秋节",
      "20260928": "中秋节",
      "20261003": "国庆节",
      "20261004": "国庆节",
      "20270101": "元旦",
    },
    exchange: {
      "2026100620260920": "国庆节",
      "2026100720261010": "国庆节",
      "2026100220261017": "国庆节",
      "2026123120270104": "学生节",
    },
  },
  "2025-2026-2": {
    semesterId: "2025-2026-2",
    name: "2025-2026学年春夏学期",
    sessionTimes: ZJU_STANDARD_SESSION_TIMES,
    startEnd: ["20260223", "20260419", "20260420", "20260614"],
    holiday: {
      "20260405": "清明节",
      "20260501": "劳动节",
      "20260619": "端午节",
    },
    dummy: {},
    exchange: {},
  },
  "2025-2026-1": {
    semesterId: "2025-2026-1",
    name: "2025-2026学年秋冬学期",
    sessionTimes: ZJU_STANDARD_SESSION_TIMES,
    startEnd: ["20250915", "20251109", "20251110", "20260104"],
    holiday: {
      "20251001": "国庆节",
      "20251002": "国庆节",
      "20251003": "国庆节",
      "20251006": "中秋节",
      "20260101": "元旦",
    },
    dummy: {},
    exchange: {},
  },
  "2024-2025-2": {
    semesterId: "2024-2025-2",
    name: "2024-2025学年春夏学期",
    sessionTimes: ZJU_STANDARD_SESSION_TIMES,
    startEnd: ["20250217", "20250413", "20250414", "20250608"],
    holiday: {
      "20250404": "清明节",
      "20250501": "劳动节",
      "20250602": "端午节",
    },
    dummy: {
      "20250405": "清明节",
      "20250406": "清明节",
      "20250503": "劳动节",
      "20250504": "劳动节",
    },
    exchange: {
      "2025050220250609": "劳动节",
      "2025050520250427": "劳动节",
    },
  },
  "2024-2025-1": {
    semesterId: "2024-2025-1",
    name: "2024-2025学年秋冬学期",
    sessionTimes: ZJU_STANDARD_SESSION_TIMES,
    startEnd: ["20240909", "20241103", "20241104", "20241229"],
    holiday: {
      "20241001": "国庆节",
      "20241002": "国庆节",
      "20241003": "国庆节",
      "20250101": "元旦",
    },
    dummy: {
      "20240915": "中秋节",
      "20241005": "国庆节",
      "20241006": "国庆节",
    },
    exchange: {
      "2024091620240914": "中秋节",
      "2024091720240921": "中秋节",
      "2024100420240929": "国庆节",
      "2024100720241012": "国庆节",
      "2024101820241026": "校运会",
    },
  },
};

export class CalendarService {
  private memCache = new Map<string, SemesterCalendarConfig>();

  /** 获取当前学期标识（如 "2026-2027-1"），完全基于权威时钟与校历推算 */
  getCurrentSemesterId(date: Date = new Date()): string {
    return getAcademicSemesterId(date);
  }

  /** 获取某学期的校历配置（优先内存/远程，回退到内置离线配置） */
  async getCalendarConfig(semesterId?: string): Promise<SemesterCalendarConfig> {
    const semId = semesterId ?? this.getCurrentSemesterId();
    const cached = this.memCache.get(semId);
    if (cached) return cached;

    // 尝试从远程获取最新的校历更新（超时设为 2000ms，避免阻断）
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 2000);
      const url = `http://calendar.celechron.top/${encodeURIComponent(semId)}.json`;
      const res = await fetch(url, { signal: controller.signal });
      clearTimeout(timer);

      if (res.ok) {
        const raw = (await res.json()) as {
          sessionTime?: [string, string][];
          startEnd?: [string, string, string, string];
          holiday?: Record<string, string>;
          dummy?: Record<string, string>;
          exchange?: Record<string, string>;
        };

        if (raw.startEnd && raw.startEnd.length === 4) {
          const config: SemesterCalendarConfig = {
            semesterId: semId,
            name: `${semId.slice(0, 9)}学年${semId.endsWith("-1") ? "秋冬" : "春夏"}学期`,
            sessionTimes: raw.sessionTime && raw.sessionTime.length > 0 ? raw.sessionTime : ZJU_STANDARD_SESSION_TIMES,
            startEnd: raw.startEnd,
            holiday: raw.holiday ?? {},
            dummy: raw.dummy ?? {},
            exchange: raw.exchange ?? {},
          };
          this.memCache.set(semId, config);
          return config;
        }
      }
    } catch {
      // 忽略网络异常，进入回退
    }

    // 回退到内置校历
    if (BUNDLED_CALENDARS[semId]) {
      const bundled = BUNDLED_CALENDARS[semId]!;
      this.memCache.set(semId, bundled);
      return bundled;
    }

    // 若内置表中未收录极远未来/过去学期，依据浙大学年通用模式智能生成近似配置
    const generated = this.generateSyntheticConfig(semId);
    this.memCache.set(semId, generated);
    return generated;
  }

  /** 获取指定日期的完整教学时段、周次、调休信息 */
  async getDateInfo(date: Date = new Date()): Promise<AcademicDateInfo> {
    const semId = this.getCurrentSemesterId(date);
    const config = await this.getCalendarConfig(semId);
    return calculateAcademicDateInfo(date, config);
  }

  /**
   * 综合日程投影：结合课表 + 考试 + 作业，生成某天的具体日程流
   */
  async getDailySchedule(params: {
    timetableEntries: TimetableEntry[];
    exams?: Exam[];
    assignments?: Assignment[];
    date?: Date | string;
    semesterId?: string;
  }): Promise<DailySchedule> {
    let targetDate: Date;
    if (!params.date) {
      targetDate = new Date();
    } else if (typeof params.date === "string") {
      // 支持 "today", "tomorrow" 或 "YYYY-MM-DD"
      const lower = params.date.toLowerCase().trim();
      const now = new Date();
      if (lower === "today" || lower === "今天") {
        targetDate = now;
      } else if (lower === "tomorrow" || lower === "明天") {
        targetDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
      } else if (lower === "yesterday" || lower === "昨天") {
        targetDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
      } else {
        const parts = lower.split("-");
        if (parts.length === 3) {
          targetDate = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        } else {
          targetDate = now;
        }
      }
    } else {
      targetDate = params.date;
    }

    const semId = params.semesterId ?? this.getCurrentSemesterId(targetDate);
    const config = await this.getCalendarConfig(semId);

    return buildDailySchedule({
      date: targetDate,
      config,
      timetableEntries: params.timetableEntries,
      exams: params.exams,
      assignments: params.assignments,
    });
  }

  /**
   * 接下来 48 小时日程流（仿照 Celechron 接下来页面）
   */
  async getUpcomingSchedule48h(params: {
    timetableEntries: TimetableEntry[];
    exams?: Exam[];
    assignments?: Assignment[];
    now?: Date;
    semesterId?: string;
  }): Promise<UpcomingSchedule48h> {
    const now = params.now ?? new Date();
    const semId = params.semesterId ?? this.getCurrentSemesterId(now);
    const config = await this.getCalendarConfig(semId);

    return buildUpcomingSchedule48h({
      now,
      config,
      timetableEntries: params.timetableEntries,
      exams: params.exams,
      assignments: params.assignments,
    });
  }

  /** 生成兜底标准学期校历 */
  private generateSyntheticConfig(semesterId: string): SemesterCalendarConfig {
    const isAutumn = semesterId.endsWith("-1");
    const startYear = Number(semesterId.slice(0, 4));

    // 秋冬常规从9月中旬周一开学，春夏常规从2月中旬周一开学
    let startEnd: [string, string, string, string];
    if (isAutumn) {
      startEnd = [
        `${startYear}0915`,
        `${startYear}1109`,
        `${startYear}1110`,
        `${startYear + 1}0104`,
      ];
    } else {
      startEnd = [
        `${startYear + 1}0220`,
        `${startYear + 1}0415`,
        `${startYear + 1}0416`,
        `${startYear + 1}0610`,
      ];
    }

    return {
      semesterId,
      name: `${semesterId.slice(0, 9)}学年${isAutumn ? "秋冬" : "春夏"}学期`,
      sessionTimes: ZJU_STANDARD_SESSION_TIMES,
      startEnd,
      holiday: {},
      dummy: {},
      exchange: {},
    };
  }
}
