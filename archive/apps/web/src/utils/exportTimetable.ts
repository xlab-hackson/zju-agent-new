/**
 * 课表导出：PNG 截图（html-to-image）+ Excel 网格（ExcelJS）。
 * 网格摆放与配色复用 utils/timetable.ts，保证导出与页面所见一致。
 *
 * PNG 由调用方（TimetablePanel）渲染一个含标题的离屏节点后传入本模块截图；
 * Excel 在浏览器端直接由 TimetableEntry 数据生成，无需后端参与。
 */

import { toPng } from "html-to-image";
// 仅类型引用（编译期擦除）；运行时在 downloadTimetableXlsx 内动态 import，
// 让 ExcelJS 独立成懒加载 chunk，不拖累课程页首屏
import type * as ExcelJS from "exceljs";
import { type TimetableEntry, mergeTimetableEntries } from "@zju-agent/core";
import {
  compressWeeks,
  courseNamesOf,
  groupTimetable,
  periodTimeRange,
  COURSE_COLOR_HEX,
  DAY_LABELS,
  DAYS,
  MAX_SECTION,
} from "./timetable.js";

/** PNG：把离屏渲染的课表节点截图并触发下载 */
export async function downloadTimetablePng(
  node: HTMLElement,
  fileName: string,
): Promise<void> {
  const dataUrl = await toPng(node, {
    pixelRatio: 2,
    backgroundColor: "#ffffff",
  });
  triggerDownload(dataUrl, fileName);
}

/** Excel：生成网格样式课表（节次×星期，跨节次纵向合并、课程配色与网页一致） */
export async function downloadTimetableXlsx(
  entries: TimetableEntry[],
  semesterLabel: string,
  fileName: string,
): Promise<void> {
  const merged = mergeTimetableEntries(entries);
  const groups = groupTimetable(merged);
  const names = courseNamesOf(merged);
  const colCount = DAYS.length + 1;

  const { Workbook } = await import("exceljs");
  const workbook = new Workbook();
  const ws = workbook.addWorksheet("课程表", {
    views: [{ state: "frozen", ySplit: 2 }],
  });
  ws.columns = [{ width: 12 }, ...DAYS.map(() => ({ width: 20 }))];

  // 标题行
  ws.mergeCells(1, 1, 1, colCount);
  const title = ws.getCell(1, 1);
  title.value = `浙江大学课程表（${semesterLabel}）  导出于 ${todayStamp()}`;
  title.font = { size: 14, bold: true, color: { argb: "FF0F172A" } };
  title.alignment = { horizontal: "center", vertical: "middle" };
  ws.getRow(1)!.height = 30;

  // 表头行
  const headerTexts = ["节次", ...DAYS.map((d) => DAY_LABELS[d]!)];
  headerTexts.forEach((text, i) => {
    const cell = ws.getCell(2, i + 1);
    cell.value = text;
    cell.font = { bold: true, size: 11, color: { argb: "FF475569" } };
    cell.alignment = { horizontal: "center", vertical: "middle" };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF1F5F9" } };
    cell.border = gridBorder();
  });

  // 节次编号列：节次 + 上课时间（与网页课表同一张作息表）
  for (let sec = 1; sec <= MAX_SECTION; sec++) {
    const row = sec + 2;
    ws.getRow(row)!.height = 54;
    const cell = ws.getCell(row, 1);
    cell.value = `${sec}\n${periodTimeRange(sec)}`;
    cell.font = { size: 10, color: { argb: "FF94A3B8" } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: "FFF8FAFC" } };
    cell.border = gridBorder();
  }

  // 课程格：与网页相同的分组、跨节合并与配色
  for (const g of groups) {
    const col = g.weekday + 1;
    const rowStart = g.startSection + 2;
    const rowEnd = Math.min(g.startSection + g.span - 1 + 2, MAX_SECTION + 2);
    const cell = ws.getCell(rowStart, col);
    cell.value = g.items
      .map((e) => courseCellLines(e).join("\n"))
      .join("\n\n");
    const name = g.items[0]?.courseName ?? "";
    const idx = Math.max(names.indexOf(name), 0);
    const palette = COURSE_COLOR_HEX[idx % COURSE_COLOR_HEX.length]!;
    cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: palette.bg } };
    cell.font = { size: 10, bold: true, color: { argb: palette.text } };
    cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
    // 合并区域内每个格子都要先画边框（合并后保留网格线）
    for (let r = rowStart; r <= rowEnd; r++) {
      ws.getCell(r, col).border = gridBorder();
    }
    if (rowEnd > rowStart) ws.mergeCells(rowStart, col, rowEnd, col);
  }

  const buffer = await workbook.xlsx.writeBuffer();
  const blob = new Blob([buffer], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  try {
    triggerDownload(url, fileName);
  } finally {
    URL.revokeObjectURL(url);
  }
}

/** 导出文件名用的时间戳，如 "20260908" */
export function todayStamp(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`;
}

function courseCellLines(e: TimetableEntry): string[] {
  const lines = [e.courseName];
  if (e.teacher) lines.push(e.teacher);
  if (e.location) lines.push(e.location);
  if (e.weeks.length > 0) lines.push(`${compressWeeks(e.weeks)}周`);
  return lines;
}

function gridBorder(): Partial<ExcelJS.Borders> {
  const edge = { style: "thin" as const, color: { argb: "FFE2E8F0" } };
  return { top: edge, left: edge, bottom: edge, right: edge };
}

function triggerDownload(href: string, fileName: string): void {
  const a = document.createElement("a");
  a.href = href;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
}
