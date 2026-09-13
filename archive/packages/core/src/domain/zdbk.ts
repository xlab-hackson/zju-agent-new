/** 本科教务网 (zdbk.zju.edu.cn) 领域类型 */

export type TimetableEntry = {
  id: string;
  courseName: string;
  teacher?: string;
  location?: string;
  weekday: number;
  startSection: number;
  endSection: number;
  weeks: number[];
  semester: string;
  /** 子学期标签：秋冬学期内的"秋"/"冬"，春夏学期内的"春"/"夏" */
  subSemester?: string;
  rawTimeText?: string;
};

export type Exam = {
  id: string;
  courseName: string;
  time?: string;
  location?: string;
  seat?: string;
  semester?: string;
};

import { getAcademicSemesterId } from "./schedule.js";

/** 当前所处的教学时段（按日期推算） */
export type AcademicPeriod =
  | { type: "semester"; term: "秋冬" | "春夏"; year: string }
  | { type: "break"; name: "寒假" | "暑假" };

export function getAcademicPeriod(date: Date = new Date()): AcademicPeriod {
  const m = date.getMonth() + 1;
  const d = date.getDate();
  if ((m === 7 && d >= 11) || (m === 8 && d <= 15)) return { type: "break", name: "暑假" };
  if (m === 1 && d >= 22 || m === 2 && d <= 15) return { type: "break", name: "寒假" };
  const semId = getAcademicSemesterId(date);
  const term: "秋冬" | "春夏" = semId.endsWith("-1") ? "秋冬" : "春夏";
  const year = semId.slice(0, 9);
  return { type: "semester", term, year };
}

export function currentXnxq01id(date: Date = new Date()): string {
  return getAcademicSemesterId(date);
}

/** 成绩（教务网）。字段参照 CeleChron Grade（lib/model/grade.dart） */
export type Grade = {
  id: string;
  courseName: string;
  /** 学分 */
  credit: number;
  /** 原始成绩：可能是百分制数字，也可能是 "优秀/良好/A+/合格/弃修" 等等级 */
  original: string;
  /** 五分制绩点 */
  fivePoint: number;
  /** 学期标识，如 "2024-2025-2"；从 xkkh 切片得到 */
  semester: string;
  /** 是否计入 GPA（弃修/待录/缓考/无效/合格/不合格/体网课不计） */
  gpaIncluded: boolean;
  /** 是否计入学分（弃修/待录/缓考/无效不计） */
  creditIncluded: boolean;
};

function areWeeksEqual(w1: number[], w2: number[]): boolean {
  if (w1.length !== w2.length) return false;
  const s1 = [...w1].sort((a, b) => a - b);
  const s2 = [...w2].sort((a, b) => a - b);
  return s1.every((v, idx) => v === s2[idx]);
}

/**
 * 合并同课程、同星期、同周次、同校区/教室的连续小节。
 * 正方教务网因课表排程粒度原因，常把下午 6-8 节等连续课程拆分为两个相邻条目
 * （如第 6 节一段，第 7-8 节一段）。本函数将其平滑缝合成单一的连续 TimetableEntry。
 */
export function mergeTimetableEntries(
  entries: TimetableEntry[],
): TimetableEntry[] {
  if (!entries || entries.length <= 1) return entries ?? [];

  // 按 课程名 + 星期 + 学期 + 子学期 分组
  const groups = new Map<string, TimetableEntry[]>();
  for (const entry of entries) {
    const key = `${entry.courseName}|${entry.weekday}|${entry.semester}|${entry.subSemester ?? ""}`;
    const list = groups.get(key) ?? [];
    list.push(entry);
    groups.set(key, list);
  }

  const result: TimetableEntry[] = [];

  for (const group of groups.values()) {
    // 按起始节次升序排序
    group.sort((a, b) => a.startSection - b.startSection);

    const merged: TimetableEntry[] = [];
    for (const item of group) {
      if (merged.length === 0) {
        merged.push({ ...item });
        continue;
      }

      const prev = merged[merged.length - 1]!;
      // 判断是否连续且属性兼容（周次一致、教师相同或缺省、地点相同或缺省）
      const isConsecutive = item.startSection <= prev.endSection + 1;
      const isWeeksCompatible = areWeeksEqual(prev.weeks, item.weeks);
      const isTeacherCompatible =
        !prev.teacher || !item.teacher || prev.teacher === item.teacher;
      const isLocationCompatible =
        !prev.location || !item.location || prev.location === item.location;

      if (
        isConsecutive &&
        isWeeksCompatible &&
        isTeacherCompatible &&
        isLocationCompatible
      ) {
        // 缝合！
        prev.endSection = Math.max(prev.endSection, item.endSection);
        prev.teacher = prev.teacher || item.teacher;
        prev.location = prev.location || item.location;
        if (prev.weeks.length === 0 && item.weeks.length > 0) {
          prev.weeks = item.weeks;
        }
      } else {
        merged.push({ ...item });
      }
    }

    result.push(...merged);
  }

  return result.sort((a, b) => {
    if (a.weekday !== b.weekday) return a.weekday - b.weekday;
    return a.startSection - b.startSection;
  });
}

