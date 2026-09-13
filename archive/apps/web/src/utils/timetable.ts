/**
 * 课表网格共享逻辑：TimetableGrid（网页渲染）与 exportTimetable（PNG/Excel 导出）
 * 共用同一套摆放与配色规则，保证导出与页面所见一致。
 */

import { ZJU_STANDARD_SESSION_TIMES, type TimetableEntry } from "@zju-agent/core";

export const DAY_LABELS = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"] as const;
export const MAX_SECTION = 13;
export const DAYS = [1, 2, 3, 4, 5, 6, 7] as const;

/**
 * 第 N 节课的起止时间，如 1 → "08:00-08:45"。
 * 直接取 core 的浙大标准作息表（与后端日程流/桌面挂件用的是同一张表，只有一处定义）；
 * 表里 index 0 是占位项，节次从 1 开始，越界返回空串。
 */
export function periodTimeRange(section: number): string {
  if (!Number.isInteger(section) || section < 1) return "";
  const slot = ZJU_STANDARD_SESSION_TIMES[section];
  return slot ? `${slot[0]}-${slot[1]}` : "";
}

/** 连续节次的时间区间，如 (1, 2) → "08:00-09:35" */
export function periodSpanTimeRange(startSection: number, endSection: number): string {
  if (
    !Number.isInteger(startSection) ||
    !Number.isInteger(endSection) ||
    startSection < 1 ||
    endSection < startSection
  ) {
    return "";
  }
  const start = ZJU_STANDARD_SESSION_TIMES[startSection]?.[0];
  const end = ZJU_STANDARD_SESSION_TIMES[endSection]?.[1];
  return start && end ? `${start}-${end}` : "";
}

/** 节次区间标签："第1-2节" / "第6节"；考试等没有节次信息的条目返回空串 */
export function sectionRangeLabel(
  startSection?: number,
  endSection?: number,
): string {
  if (!startSection || !endSection || endSection < startSection) return "";
  return startSection === endSection
    ? `第${startSection}节`
    : `第${startSection}-${endSection}节`;
}

/**
 * 网页端课程块配色（纸墨学术风·传统色），按课程名首次出现顺序循环取色。
 * 靛蓝 / 竹青 / 赭黄 / 胭脂 / 紫藤 / 黛青 / 藤黄 / 墨灰——
 * 低饱和暖调，与纸色底 (paper) 协调；类名静态写在源码里供 Tailwind JIT 扫描。
 */
export const COURSE_COLORS = [
  "bg-[#e3ebf6] border-[#a8bcd8] text-[#1c3a63]", // 靛蓝
  "bg-[#e2efe3] border-[#a5c9a8] text-[#2c5e33]", // 竹青
  "bg-[#f5ecd9] border-[#dbc493] text-[#7a5f22]", // 赭黄
  "bg-[#f6e3df] border-[#ddb0a6] text-[#8c3a2e]", // 胭脂
  "bg-[#eae5f2] border-[#bfb2d6] text-[#55447a]", // 紫藤
  "bg-[#e0edee] border-[#a3c6c9] text-[#2a5a5e]", // 黛青
  "bg-[#f7e9dc] border-[#e0b994] text-[#8a5222]", // 藤黄
  "bg-[#e9e7e0] border-[#c2bfb2] text-[#4a4a42]", // 墨灰
] as const;

/** Excel 导出配色：与 COURSE_COLORS 一一对应（ARGB 加 FF 前缀） */
export const COURSE_COLOR_HEX = [
  { bg: "FFE3EBF6", border: "FFA8BCD8", text: "FF1C3A63" }, // 靛蓝
  { bg: "FFE2EFE3", border: "FFA5C9A8", text: "FF2C5E33" }, // 竹青
  { bg: "FFF5ECD9", border: "FFDBC493", text: "FF7A5F22" }, // 赭黄
  { bg: "FFF6E3DF", border: "FFDDB0A6", text: "FF8C3A2E" }, // 胭脂
  { bg: "FFEAE5F2", border: "FFBFB2D6", text: "FF55447A" }, // 紫藤
  { bg: "FFE0EDEE", border: "FFA3C6C9", text: "FF2A5A5E" }, // 黛青
  { bg: "FFF7E9DC", border: "FFE0B994", text: "FF8A5222" }, // 藤黄
  { bg: "FFE9E7E0", border: "FFC2BFB2", text: "FF4A4A42" }, // 墨灰
] as const;

export type CourseGroup = {
  weekday: number;
  startSection: number;
  /** 组内最大跨节数（同格多门课时容器按最高课拉伸） */
  span: number;
  items: TimetableEntry[];
};

/** 按起始格分组：同天同起始节的多门课并排渲染 */
export function groupTimetable(entries: TimetableEntry[]): CourseGroup[] {
  const map = new Map<string, CourseGroup>();
  for (const e of entries) {
    const key = `${e.weekday}-${e.startSection}`;
    const g =
      map.get(key) ??
      { weekday: e.weekday, startSection: e.startSection, span: 0, items: [] };
    g.items.push(e);
    g.span = Math.max(g.span, e.endSection - e.startSection + 1);
    map.set(key, g);
  }
  return [...map.values()];
}

/** 课程名列表（首次出现顺序），供取色循环 */
export function courseNamesOf(entries: TimetableEntry[]): string[] {
  return [...new Set(entries.map((e) => e.courseName))];
}

export function compressWeeks(weeks: number[]): string {
  if (weeks.length === 0) return "";
  const sorted = [...new Set(weeks)].sort((a, b) => a - b);
  const parts: string[] = [];
  let start = sorted[0]!;
  let prev = sorted[0]!;
  for (let i = 1; i < sorted.length; i++) {
    const cur = sorted[i]!;
    if (cur !== prev + 1) {
      parts.push(start === prev ? `${start}` : `${start}-${prev}`);
      start = cur;
    }
    prev = cur;
  }
  parts.push(start === prev ? `${start}` : `${start}-${prev}`);
  return parts.join(",");
}

/** 教务网学期 id → 显示名，如 "2026-2027-1" → "2026-2027学年秋冬学期" */
export function semesterDisplayName(xnxq01id: string): string {
  const year = xnxq01id.slice(0, 9);
  if (xnxq01id.endsWith("-2")) return `${year}学年春夏学期`;
  if (xnxq01id.endsWith("-3")) return `${year}学年短学期`;
  return `${year}学年秋冬学期`;
}
