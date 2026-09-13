import { describe, expect, it } from "vitest";
import { mergeTimetableEntries, type TimetableEntry } from "./zdbk.js";

function entry(partial: Partial<TimetableEntry> & Pick<TimetableEntry, "id" | "courseName" | "weekday" | "startSection" | "endSection">): TimetableEntry {
  return {
    weeks: [1, 2, 3],
    semester: "2025-2026-1",
    ...partial,
  };
}

describe("mergeTimetableEntries", () => {
  it("空数组与单条目原样返回", () => {
    expect(mergeTimetableEntries([])).toEqual([]);
    const single = [entry({ id: "a", courseName: "高数", weekday: 1, startSection: 1, endSection: 2 })];
    expect(mergeTimetableEntries(single)).toEqual(single);
  });

  it("缝合同课程同天连续节次（正方拆分场景：第6节一段、第7-8节一段）", () => {
    const input = [
      entry({ id: "a", courseName: "高数", weekday: 1, startSection: 6, endSection: 6, location: "教十一-304" }),
      entry({ id: "b", courseName: "高数", weekday: 1, startSection: 7, endSection: 8, location: "教十一-304" }),
    ];
    const out = mergeTimetableEntries(input);
    expect(out).toHaveLength(1);
    expect(out[0]!.startSection).toBe(6);
    expect(out[0]!.endSection).toBe(8);
  });

  it("教师/地点一方缺省时取另一方补全", () => {
    const input = [
      entry({ id: "a", courseName: "高数", weekday: 2, startSection: 1, endSection: 2, teacher: "张三" }),
      entry({ id: "b", courseName: "高数", weekday: 2, startSection: 3, endSection: 4, location: "紫金港-东二" }),
    ];
    const out = mergeTimetableEntries(input);
    expect(out).toHaveLength(1);
    expect(out[0]!.teacher).toBe("张三");
    expect(out[0]!.location).toBe("紫金港-东二");
  });

  it("周次不同则不缝合", () => {
    const input = [
      entry({ id: "a", courseName: "高数", weekday: 3, startSection: 1, endSection: 2, weeks: [1, 2] }),
      entry({ id: "b", courseName: "高数", weekday: 3, startSection: 3, endSection: 4, weeks: [3, 4] }),
    ];
    expect(mergeTimetableEntries(input)).toHaveLength(2);
  });

  it("教师不同则不缝合", () => {
    const input = [
      entry({ id: "a", courseName: "高数", weekday: 4, startSection: 1, endSection: 2, teacher: "张三" }),
      entry({ id: "b", courseName: "高数", weekday: 4, startSection: 3, endSection: 4, teacher: "李四" }),
    ];
    expect(mergeTimetableEntries(input)).toHaveLength(2);
  });

  it("节次不连续（间隔≥2）则不缝合", () => {
    const input = [
      entry({ id: "a", courseName: "高数", weekday: 5, startSection: 1, endSection: 2 }),
      entry({ id: "b", courseName: "高数", weekday: 5, startSection: 4, endSection: 5 }),
    ];
    expect(mergeTimetableEntries(input)).toHaveLength(2);
  });

  it("不同子学期（秋/冬）不缝合", () => {
    const input = [
      entry({ id: "a", courseName: "高数", weekday: 1, startSection: 1, endSection: 2, subSemester: "秋" }),
      entry({ id: "b", courseName: "高数", weekday: 1, startSection: 3, endSection: 4, subSemester: "冬" }),
    ];
    expect(mergeTimetableEntries(input)).toHaveLength(2);
  });

  it("三条连续链式缝合为一条", () => {
    const input = [
      entry({ id: "a", courseName: "英语", weekday: 2, startSection: 6, endSection: 6 }),
      entry({ id: "b", courseName: "英语", weekday: 2, startSection: 7, endSection: 7 }),
      entry({ id: "c", courseName: "英语", weekday: 2, startSection: 8, endSection: 9 }),
    ];
    const out = mergeTimetableEntries(input);
    expect(out).toHaveLength(1);
    expect(out[0]!.startSection).toBe(6);
    expect(out[0]!.endSection).toBe(9);
  });

  it("输入对象不被修改（浅拷贝语义）", () => {
    const a = entry({ id: "a", courseName: "高数", weekday: 1, startSection: 1, endSection: 2 });
    const b = entry({ id: "b", courseName: "高数", weekday: 1, startSection: 3, endSection: 4 });
    const originalEnd = a.endSection;
    mergeTimetableEntries([a, b]);
    expect(a.endSection).toBe(originalEnd);
  });

  it("输出按星期、起始节次排序", () => {
    const input = [
      entry({ id: "a", courseName: "高数", weekday: 5, startSection: 1, endSection: 2 }),
      entry({ id: "b", courseName: "英语", weekday: 1, startSection: 6, endSection: 8 }),
      entry({ id: "c", courseName: "物理", weekday: 1, startSection: 1, endSection: 2 }),
    ];
    const out = mergeTimetableEntries(input);
    expect(out.map((e) => e.courseName)).toEqual(["物理", "英语", "高数"]);
  });
});
