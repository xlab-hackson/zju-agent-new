/**
 * 浙大校历与日程领域类型与算法（借鉴 Celechron 日程时空坐标系重构）
 * 见 docs/celechron-schedule-reference.md
 */

import type { TimetableEntry, Exam } from "./zdbk.js";
import type { Assignment } from "./courses.js";

export type ZjuSessionTime = [string, string];

export const ZJU_STANDARD_SESSION_TIMES: ZjuSessionTime[] = [
  ["00:00", "00:00"], // index 0 占位
  ["08:00", "08:45"], // 1
  ["08:50", "09:35"], // 2
  ["10:00", "10:45"], // 3
  ["10:50", "11:35"], // 4
  ["11:40", "12:25"], // 5
  ["13:25", "14:10"], // 6
  ["14:15", "15:00"], // 7
  ["15:05", "15:50"], // 8
  ["16:15", "17:00"], // 9
  ["17:05", "17:50"], // 10
  ["18:50", "19:35"], // 11
  ["19:40", "20:25"], // 12
  ["20:30", "21:15"], // 13
  ["21:20", "22:05"], // 14
  ["22:10", "22:55"], // 15
];

export type ZjuCalendarRaw = {
  sessionTime?: [string, string][];
  startEnd?: [string, string, string, string]; // [half1Start, half1End, half2Start, half2End]
  holiday?: Record<string, string>;
  dummy?: Record<string, string>;
  exchange?: Record<string, string>;
};

export type SemesterCalendarConfig = {
  semesterId: string; // e.g. "2026-2027-1"
  name: string; // e.g. "2026-2027学年秋冬学期"
  sessionTimes: ZjuSessionTime[];
  startEnd: [string, string, string, string]; // 格式均为 YYYYMMDD
  holiday: Record<string, string>; // YYYYMMDD -> 节日名
  dummy: Record<string, string>;
  exchange: Record<string, string>; // YYYYMMDDYYYYMMDD -> 节日名
};

export type AcademicPeriodType = "instruction" | "exam" | "break" | "preparation";

export type AcademicDateInfo = {
  date: string; // YYYY-MM-DD
  semesterId: string; // "2026-2027-1"
  academicYear: string; // "2026-2027"
  term: "秋冬" | "春夏";
  periodType: AcademicPeriodType;
  subTerm?: "秋" | "冬" | "春" | "夏";
  week: number; // 教学周 1..16，非教学周为 0
  weekString: string; // "秋第1周", "第1周", "考试周", "假期", "开学前夕"
  weekday: number; // 1..7 (周一为1)
  isHoliday: boolean; // 是否放假停课
  holidayName?: string;
  isMakeupDay: boolean; // 是否是调休补课日
  makeupTargetDate?: string; // 补哪一天的课 (YYYY-MM-DD)
  effectiveWeekday: number; // 实际执行课表的星期几 (1..7)。放假为 0
};

export type ScheduleEventType = "class" | "exam" | "assignment";

export type ScheduleEvent = {
  id: string;
  type: ScheduleEventType;
  title: string;
  courseId?: string;
  courseName?: string;
  teacher?: string;
  location?: string;
  seat?: string;
  date: string; // YYYY-MM-DD
  startTime: string; // HH:mm
  endTime: string; // HH:mm
  startSection?: number;
  endSection?: number;
  description?: string;
  status?: string;
};

export type DailySchedule = {
  date: string;
  dateInfo: AcademicDateInfo;
  events: ScheduleEvent[];
  summary: string;
};

/** 日期工具：格式化为 YYYY-MM-DD */
export function formatDateIso(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** 日期工具：格式化为 YYYYMMDD */
export function formatDateCompact(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}${m}${d}`;
}

/** 解析 YYYYMMDD 为本地 Date (00:00:00) */
export function parseDateCompact(compact: string): Date {
  const y = Number(compact.slice(0, 4));
  const m = Number(compact.slice(4, 6)) - 1;
  const d = Number(compact.slice(6, 8));
  return new Date(y, m, d);
}

/** 规范化任何日期为本地零点 Date */
export function toMidnight(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

/** 两个日期之间的自然天数差 (b - a) */
export function daysBetween(a: Date, b: Date): number {
  const ma = toMidnight(a).getTime();
  const mb = toMidnight(b).getTime();
  return Math.round((mb - ma) / (24 * 60 * 60 * 1000));
}

/**
 * 根据公历日期推算浙大学期标识 (xnxq01id)。
 * 浙大常规学年安排：
 * - 8月下半月 ~ 次年1月下旬: 秋冬学期 (${year}-${year+1}-1)
 * - 2月中旬 ~ 7月上旬: 春夏学期 (${year-1}-${year}-2)
 * - 7月中旬 ~ 8月中旬: 暑假或短学期，按即将开始的新学年秋冬学期计算
 */
export function getAcademicSemesterId(date: Date = new Date()): string {
  const m = date.getMonth() + 1;
  const d = date.getDate();
  const y = date.getFullYear();

  // 1月25日之前属于当年秋冬
  if (m === 1 && d <= 25) {
    return `${y - 1}-${y}-1`;
  }
  // 1月26日 ~ 7月10日属于当年春夏
  if (m <= 6 || (m === 7 && d <= 10)) {
    return `${y - 1}-${y}-2`;
  }
  // 7月11日之后均视作新学年的秋冬学期（含暑假开学筹备）
  return `${y}-${y + 1}-1`;
}

/**
 * 根据校历配置推算具体日期的教学信息（周次、放假、调休、有效星期几）。
 */
export function calculateAcademicDateInfo(
  date: Date,
  config: SemesterCalendarConfig,
): AcademicDateInfo {
  const target = toMidnight(date);
  const dateIso = formatDateIso(target);
  const compact = formatDateCompact(target);
  const rawWeekday = target.getDay() === 0 ? 7 : target.getDay();

  const [h1StartStr, h1EndStr, h2StartStr, h2EndStr] = config.startEnd;
  const h1Start = parseDateCompact(h1StartStr);
  const h1End = parseDateCompact(h1EndStr);
  const h2Start = parseDateCompact(h2StartStr);
  const h2End = parseDateCompact(h2EndStr);

  const isAutumnTerm = config.semesterId.endsWith("-1");
  const term: "秋冬" | "春夏" = isAutumnTerm ? "秋冬" : "春夏";
  const academicYear = config.semesterId.slice(0, 9);

  let periodType: AcademicPeriodType = "instruction";
  let subTerm: "秋" | "冬" | "春" | "夏" | undefined;
  let week = 0;
  let weekString = "";

  if (target < h1Start) {
    periodType = "preparation";
    const daysBefore = daysBetween(target, h1Start);
    weekString = daysBefore <= 7 ? "开学前夕" : "假期/开学准备";
  } else if (target <= h1End) {
    periodType = "instruction";
    subTerm = isAutumnTerm ? "秋" : "春";
    week = Math.floor(daysBetween(h1Start, target) / 7) + 1;
    weekString = `${subTerm}第${week}周`;
  } else if (target < h2Start) {
    periodType = "instruction";
    subTerm = isAutumnTerm ? "秋" : "春";
    week = 8;
    weekString = `${subTerm}期末`;
  } else if (target <= h2End) {
    periodType = "instruction";
    subTerm = isAutumnTerm ? "冬" : "夏";
    week = Math.floor(daysBetween(h2Start, target) / 7) + 9;
    const subWeek = week - 8;
    weekString = `${subTerm}第${subWeek}周 (总第${week}周)`;
  } else {
    // 超过后半学期教学周：进入考试周或假期
    const daysAfterH2 = daysBetween(h2End, target);
    if (daysAfterH2 <= 14) {
      periodType = "exam";
      weekString = "期末考试周";
    } else {
      periodType = "break";
      weekString = isAutumnTerm ? "寒假" : "暑假";
    }
  }

  // 节假日与调休判定
  let isHoliday = false;
  let holidayName: string | undefined;
  let isMakeupDay = false;
  let makeupTargetDate: string | undefined;
  let effectiveWeekday = rawWeekday;

  // 1. 检查是否直接放假（在 holiday 中）
  if (config.holiday[compact]) {
    isHoliday = true;
    holidayName = config.holiday[compact];
  }

  // 2. 检查调休对（exchange: "原放假日YYYYMMDD补课公历日YYYYMMDD"）
  for (const [key, fest] of Object.entries(config.exchange)) {
    if (key.length === 16) {
      const origCompact = key.slice(0, 8);
      const makeupCompact = key.slice(8, 16);

      // 如果当前日期是原放假日，且有对应调休
      if (compact === origCompact) {
        isHoliday = true;
        holidayName = holidayName ?? `${fest}调休放假`;
      }
      // 如果当前日期是补课日
      if (compact === makeupCompact) {
        isMakeupDay = true;
        const origDate = parseDateCompact(origCompact);
        const origWeekday = origDate.getDay() === 0 ? 7 : origDate.getDay();
        effectiveWeekday = origWeekday;
        makeupTargetDate = formatDateIso(origDate);
        holidayName = `${fest}调课（补${origDate.getMonth() + 1}月${origDate.getDate()}日周${["一","二","三","四","五","六","日"][origWeekday - 1]}课程）`;
      }
    }
  }

  // 若当天放假且未调休补课，有效星期设为 0
  if (isHoliday && !isMakeupDay) {
    effectiveWeekday = 0;
  }

  return {
    date: dateIso,
    semesterId: config.semesterId,
    academicYear,
    term,
    periodType,
    subTerm,
    week,
    weekString,
    weekday: rawWeekday,
    isHoliday,
    holidayName,
    isMakeupDay,
    makeupTargetDate,
    effectiveWeekday,
  };
}

/**
 * 将抽象课表 (TimetableEntry[]) 根据校历投影到具体某一天。
 */
export function projectTimetableToDay(
  entries: TimetableEntry[],
  date: Date,
  config: SemesterCalendarConfig,
): ScheduleEvent[] {
  const dateInfo = calculateAcademicDateInfo(date, config);
  // 放假不补课直接返回空
  if (dateInfo.isHoliday && !dateInfo.isMakeupDay) {
    return [];
  }
  // 非教学周且非调课日无课
  if (dateInfo.periodType !== "instruction" && !dateInfo.isMakeupDay) {
    return [];
  }

  const targetWeekday = dateInfo.effectiveWeekday;
  const currentWeek = dateInfo.week;
  const currentSub = dateInfo.subTerm;
  const sessionTimes = config.sessionTimes.length > 0 ? config.sessionTimes : ZJU_STANDARD_SESSION_TIMES;

  const events: ScheduleEvent[] = [];

  for (const entry of entries) {
    // 星期过滤
    if (entry.weekday !== targetWeekday) continue;

    // 周次过滤：课程周次列表必须包含当前教学周
    if (currentWeek > 0 && entry.weeks.length > 0 && !entry.weeks.includes(currentWeek)) {
      continue;
    }

    // 子学期过滤：如课程标明为“秋”，而当前是“冬”，则跳过
    if (entry.subSemester && currentSub && entry.subSemester !== currentSub) {
      // 允许“春夏”或“秋冬”跨段课程
      if (!entry.subSemester.includes(currentSub)) {
        continue;
      }
    }

    const startSec = entry.startSection;
    const endSec = entry.endSection;
    const startTime = sessionTimes[startSec]?.[0] ?? "08:00";
    const endTime = sessionTimes[endSec]?.[1] ?? "08:45";

    events.push({
      id: `${entry.id}-${dateInfo.date}-${startSec}`,
      type: "class",
      title: entry.courseName,
      courseId: entry.id,
      courseName: entry.courseName,
      teacher: entry.teacher,
      location: entry.location,
      date: dateInfo.date,
      startTime,
      endTime,
      startSection: startSec,
      endSection: endSec,
      description: `第${startSec}-${endSec}节 ${entry.teacher ? `| 教师: ${entry.teacher}` : ""}`,
    });
  }

  return events.sort((a, b) => a.startTime.localeCompare(b.startTime));
}

/**
 * 聚合某日的全部日程（课程 + 当天考试 + 当天截止作业）。
 */
export function buildDailySchedule(params: {
  date: Date;
  config: SemesterCalendarConfig;
  timetableEntries: TimetableEntry[];
  exams?: Exam[];
  assignments?: Assignment[];
}): DailySchedule {
  const { date, config, timetableEntries, exams = [], assignments = [] } = params;
  const dateInfo = calculateAcademicDateInfo(date, config);
  const events = projectTimetableToDay(timetableEntries, date, config);
  const dateIso = dateInfo.date;

  // 合并考试
  for (const exam of exams) {
    if (!exam.time) continue;
    // 考试 time 格式如 "2026-10-15 08:30-10:30" 或 "2026-10-15"
    if (exam.time.startsWith(dateIso)) {
      const match = exam.time.match(/(\d{2}:\d{2})-(\d{2}:\d{2})/);
      const startTime = match?.[1] ?? "08:30";
      const endTime = match?.[2] ?? "10:30";
      events.push({
        id: `exam-${exam.id}-${dateIso}`,
        type: "exam",
        title: `[考试] ${exam.courseName}`,
        courseName: exam.courseName,
        location: exam.location ?? "详见教务网",
        seat: exam.seat,
        date: dateIso,
        startTime,
        endTime,
        description: `考场: ${exam.location ?? "未公布"} | 座位号: ${exam.seat ?? "未指定"}`,
      });
    }
  }

  // 合并作业（截止于当天的作业）
  for (const a of assignments) {
    if (a.submitted) continue;
    if (a.deadline && a.deadline.startsWith(dateIso)) {
      const timeMatch = a.deadline.match(/T?(\d{2}:\d{2})/);
      const dueTime = timeMatch?.[1] ?? "23:59";
      events.push({
        id: `assign-${a.id}-${dateIso}`,
        type: "assignment",
        title: `[DDL] ${a.title}`,
        courseId: a.courseId,
        courseName: a.courseName,
        date: dateIso,
        startTime: dueTime,
        endTime: dueTime,
        status: "pending",
        description: `课程: ${a.courseName} | 截止时间: ${dueTime}`,
      });
    }
  }

  // 按时间排序
  events.sort((a, b) => a.startTime.localeCompare(b.startTime));

  // 摘要文字生成
  let summary = "";
  if (dateInfo.isHoliday && !dateInfo.isMakeupDay) {
    summary = `${dateInfo.holidayName ?? "放假"}，今日无教学课程。`;
  } else if (events.length === 0) {
    summary = `今日暂无课程、考试或待办作业（${dateInfo.weekString}）。`;
  } else {
    const classCount = events.filter((e) => e.type === "class").length;
    const examCount = events.filter((e) => e.type === "exam").length;
    const ddlCount = events.filter((e) => e.type === "assignment").length;
    const parts: string[] = [];
    if (classCount > 0) parts.push(`${classCount}门课程`);
    if (examCount > 0) parts.push(`${examCount}场考试`);
    if (ddlCount > 0) parts.push(`${ddlCount}项作业截止`);
    summary = `${dateInfo.weekString}，今日共 ${parts.join("、")}。`;
    if (dateInfo.isMakeupDay) {
      summary = `【调休补课】${summary}（${dateInfo.holidayName}）`;
    }
  }

  return {
    date: dateIso,
    dateInfo,
    events,
    summary,
  };
}

// ==================== 仿照 Celechron 的 48 小时日程流体系 ====================

export type UpcomingPeriodType = "class" | "exam" | "event";
export type UpcomingPeriodStatus = "ongoing" | "upcoming";

export type UpcomingPeriod = {
  id: string;
  type: UpcomingPeriodType;
  status: UpcomingPeriodStatus;
  title: string;
  courseName?: string;
  teacher?: string;
  location: string;
  seat?: string;
  date: string; // YYYY-MM-DD
  startIso: string;
  endIso: string;
  startTimeStr: string; // "08:00"
  endTimeStr: string; // "09:35"
  friendlyDateStr: string; // "今天" / "明天" / "后天"
  friendlyTimeStr: string; // "今天 08:00 - 09:35"
  remainingSeconds: number; // ongoing: 秒到结束; upcoming: 秒到开始
  progressPercent?: number; // 0..100 (仅 ongoing 期间)
  startSection?: number;
  endSection?: number;
  description?: string;
};

export type UpcomingAssignment = {
  id: string;
  title: string;
  courseId: string;
  courseName: string;
  deadline: string;
  deadlineIso: string;
  dueTimeStr: string; // "今天 23:59 截止"
  remainingSeconds: number; // 距离截止还有多少秒
  submitted: boolean;
};

export type UpcomingSchedule48h = {
  generatedAt: string; // 当前时间 ISO
  dateInfo: AcademicDateInfo;
  activePeriod?: UpcomingPeriod; // 首项：正在进行（如果有）或 即将开始的第1项
  laterPeriods: UpcomingPeriod[]; // 之后的安排（除去 activePeriod 后的后续 48h 列表）
  allPeriods: UpcomingPeriod[]; // 48h 内所有有效日程（包含 ongoing 和 upcoming，不含已结束）
  assignments48h: UpcomingAssignment[]; // 48h 内截止的未提交作业
  summary: string;
};

/** 将秒数格式化为中文时长（如 "1小时25分"、"45秒"） */
export function formatDurationChinese(seconds: number): string {
  if (seconds <= 0) return "0秒";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) {
    return `${h}小时${m}分`;
  }
  if (m > 0) {
    return `${m}分${s}秒`;
  }
  return `${s}秒`;
}

/**
 * 聚合未来 48 小时日程（仿照 Celechron 的“接下来”页面逻辑）。
 * 过滤已结束事项，按公历绝对时间升序排列，标记正在进行与即将开始，
 * 同时检索 48 小时内即将截止的作业。
 */
export function buildUpcomingSchedule48h(params: {
  now?: Date;
  config: SemesterCalendarConfig;
  timetableEntries: TimetableEntry[];
  exams?: Exam[];
  assignments?: Assignment[];
}): UpcomingSchedule48h {
  const { config, timetableEntries, exams = [], assignments = [] } = params;
  const now = params.now ?? new Date();
  const nowMs = now.getTime();
  const horizonMs = nowMs + 48 * 60 * 60 * 1000;

  const dateInfo = calculateAcademicDateInfo(now, config);

  // 1. 获取未来 3 天的日历投影（涵盖当前时间到 48 小时后）
  const days: Date[] = [
    toMidnight(now),
    new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1),
    new Date(now.getFullYear(), now.getMonth(), now.getDate() + 2),
  ];

  const rawPeriods: UpcomingPeriod[] = [];

  for (const day of days) {
    const dayEvents = projectTimetableToDay(timetableEntries, day, config);
    for (const ev of dayEvents) {
      const parts = ev.date.split("-");
      if (parts.length !== 3) continue;
      const y = Number(parts[0]);
      const m = Number(parts[1]) - 1;
      const d = Number(parts[2]);

      const [startH, startM] = ev.startTime.split(":").map(Number);
      const [endH, endM] = ev.endTime.split(":").map(Number);

      const startDt = new Date(y, m, d, startH, startM, 0);
      const endDt = new Date(y, m, d, endH, endM, 0);
      const startMs = startDt.getTime();
      const endMs = endDt.getTime();

      // 已经结束的日程跳过
      if (endMs <= nowMs) continue;
      // 超过 48 小时窗口的跳过
      if (startMs > horizonMs) continue;

      const isOngoing = startMs <= nowMs && nowMs < endMs;
      const status: UpcomingPeriodStatus = isOngoing ? "ongoing" : "upcoming";
      const remainingSeconds = isOngoing
        ? Math.max(0, Math.floor((endMs - nowMs) / 1000))
        : Math.max(0, Math.floor((startMs - nowMs) / 1000));

      const progressPercent = isOngoing
        ? Math.min(100, Math.max(0, Math.round(((nowMs - startMs) / (endMs - startMs)) * 100)))
        : 0;

      const diffDays = daysBetween(toMidnight(now), toMidnight(startDt));
      const friendlyDateStr =
        diffDays === 0 ? "今天" : diffDays === 1 ? "明天" : diffDays === 2 ? "后天" : `${m + 1}月${d}日`;
      const friendlyTimeStr = `${friendlyDateStr} ${ev.startTime} - ${ev.endTime}`;

      rawPeriods.push({
        id: ev.id,
        type: "class",
        status,
        title: ev.title,
        courseName: ev.courseName,
        teacher: ev.teacher,
        location: ev.location ?? "未安排教室",
        date: ev.date,
        startIso: startDt.toISOString(),
        endIso: endDt.toISOString(),
        startTimeStr: ev.startTime,
        endTimeStr: ev.endTime,
        friendlyDateStr,
        friendlyTimeStr,
        remainingSeconds,
        progressPercent,
        startSection: ev.startSection,
        endSection: ev.endSection,
        description: ev.description,
      });
    }
  }

  // 2. 检查 48 小时内的考试
  for (const ex of exams) {
    if (!ex.time) continue;
    // 匹配如 "2026-09-15 08:30-10:30" 或 "2026-09-15"
    const match = ex.time.match(/(\d{4}-\d{2}-\d{2})(?:\s+(\d{2}:\d{2})-(\d{2}:\d{2}))?/);
    if (!match) continue;

    const dateStr = match[1];
    if (!dateStr) continue;
    const startTimeStr = match[2] ?? "08:30";
    const endTimeStr = match[3] ?? "10:30";

    const parts = dateStr.split("-");
    const y = Number(parts[0]);
    const m = Number(parts[1]) - 1;
    const d = Number(parts[2]);

    const [startH, startM] = (startTimeStr ?? "08:30").split(":").map(Number);
    const [endH, endM] = (endTimeStr ?? "10:30").split(":").map(Number);

    const startDt = new Date(y, m, d, startH, startM, 0);
    const endDt = new Date(y, m, d, endH, endM, 0);
    const startMs = startDt.getTime();
    const endMs = endDt.getTime();

    if (endMs <= nowMs || startMs > horizonMs) continue;

    const isOngoing = startMs <= nowMs && nowMs < endMs;
    const status: UpcomingPeriodStatus = isOngoing ? "ongoing" : "upcoming";
    const remainingSeconds = isOngoing
      ? Math.max(0, Math.floor((endMs - nowMs) / 1000))
      : Math.max(0, Math.floor((startMs - nowMs) / 1000));

    const progressPercent = isOngoing
      ? Math.min(100, Math.max(0, Math.round(((nowMs - startMs) / (endMs - startMs)) * 100)))
      : 0;

    const diffDays = daysBetween(toMidnight(now), toMidnight(startDt));
    const friendlyDateStr =
      diffDays === 0 ? "今天" : diffDays === 1 ? "明天" : diffDays === 2 ? "后天" : `${m + 1}月${d}日`;
    const friendlyTimeStr = `${friendlyDateStr} ${startTimeStr} - ${endTimeStr}`;

    rawPeriods.push({
      id: `exam-${ex.id}-${dateStr}`,
      type: "exam",
      status,
      title: `[考试] ${ex.courseName}`,
      courseName: ex.courseName,
      location: ex.location ?? "考场详见教务网",
      seat: ex.seat,
      date: dateStr,
      startIso: startDt.toISOString(),
      endIso: endDt.toISOString(),
      startTimeStr,
      endTimeStr,
      friendlyDateStr,
      friendlyTimeStr,
      remainingSeconds,
      progressPercent,
      description: `考场: ${ex.location ?? "未公布"} | 座位号: ${ex.seat ?? "未指定"}`,
    });
  }

  // 按开始时间正序排序
  rawPeriods.sort((a, b) => a.startIso.localeCompare(b.startIso));

  const activePeriod = rawPeriods.length > 0 ? rawPeriods[0] : undefined;
  const laterPeriods = rawPeriods.length > 1 ? rawPeriods.slice(1) : [];

  // 3. 收集 48 小时内即将截止的作业
  const assignments48h: UpcomingAssignment[] = [];
  for (const a of assignments) {
    if (a.submitted || !a.deadline) continue;
    const dMs = Date.parse(a.deadline);
    if (Number.isNaN(dMs)) continue;
    if (dMs >= nowMs && dMs <= horizonMs) {
      const dDate = new Date(dMs);
      const diffDays = daysBetween(toMidnight(now), toMidnight(dDate));
      const prefix =
        diffDays === 0
          ? "今天"
          : diffDays === 1
            ? "明天"
            : diffDays === 2
              ? "后天"
              : `${dDate.getMonth() + 1}月${dDate.getDate()}日`;
      const hh = String(dDate.getHours()).padStart(2, "0");
      const mm = String(dDate.getMinutes()).padStart(2, "0");
      const dueTimeStr = `${prefix} ${hh}:${mm} 截止`;
      const remainingSeconds = Math.max(0, Math.floor((dMs - nowMs) / 1000));

      assignments48h.push({
        id: a.id,
        title: a.title,
        courseId: a.courseId,
        courseName: a.courseName,
        deadline: a.deadline,
        deadlineIso: dDate.toISOString(),
        dueTimeStr,
        remainingSeconds,
        submitted: false,
      });
    }
  }

  assignments48h.sort((a, b) => a.remainingSeconds - b.remainingSeconds);

  // 4. 生成中文摘要
  let summary = "";
  if (activePeriod) {
    if (activePeriod.status === "ongoing") {
      summary += `当前正在进行：${activePeriod.title}（${activePeriod.location}，离结束还有 ${formatDurationChinese(activePeriod.remainingSeconds)}）。`;
    } else {
      summary += `下一项日程：${activePeriod.title}（${activePeriod.friendlyTimeStr}，${activePeriod.location}，离开始还有 ${formatDurationChinese(activePeriod.remainingSeconds)}）。`;
    }
    if (laterPeriods.length > 0) {
      summary += `接下来的48小时内还有 ${laterPeriods.length} 项日程安排。`;
    }
  } else {
    summary += "接下来的48小时内暂无课程或考试安排。";
  }

  if (assignments48h.length > 0) {
    const nearest = assignments48h[0];
    const nearestDesc = nearest ? `（最近一项：《${nearest.title}》，${nearest.dueTimeStr}）` : "";
    summary += ` 48小时内有 ${assignments48h.length} 项作业即将截止${nearestDesc}。`;
  } else {
    summary += " 48小时内暂无即将截止的作业。";
  }

  return {
    generatedAt: now.toISOString(),
    dateInfo,
    activePeriod,
    laterPeriods,
    allPeriods: rawPeriods,
    assignments48h,
    summary,
  };
}

