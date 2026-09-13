import { describe, expect, it } from "vitest";
import {
  MAX_SECTION,
  periodSpanTimeRange,
  periodTimeRange,
  sectionRangeLabel,
} from "../utils/timetable.js";

/** 浙大标准作息（1-13 节）——课表网格与 Excel 导出都按这张表显示 */
const EXPECTED = [
  "08:00-08:45",
  "08:50-09:35",
  "10:00-10:45",
  "10:50-11:35",
  "11:40-12:25",
  "13:25-14:10",
  "14:15-15:00",
  "15:05-15:50",
  "16:15-17:00",
  "17:05-17:50",
  "18:50-19:35",
  "19:40-20:25",
  "20:30-21:15",
];

describe("periodTimeRange", () => {
  it("1-13 节课的起止时间与浙大作息一致", () => {
    for (let section = 1; section <= MAX_SECTION; section++) {
      expect(periodTimeRange(section)).toBe(EXPECTED[section - 1]);
    }
  });

  it("越界节次返回空串", () => {
    expect(periodTimeRange(0)).toBe("");
    expect(periodTimeRange(99)).toBe("");
  });
});

describe("periodSpanTimeRange", () => {
  it("连排节次取首节开始到末节结束", () => {
    expect(periodSpanTimeRange(1, 2)).toBe("08:00-09:35");
    expect(periodSpanTimeRange(3, 5)).toBe("10:00-12:25");
    expect(periodSpanTimeRange(11, 13)).toBe("18:50-21:15");
  });

  it("越界返回空串", () => {
    expect(periodSpanTimeRange(0, 1)).toBe("");
    expect(periodSpanTimeRange(13, 99)).toBe("");
  });
});

describe("sectionRangeLabel", () => {
  it("连排显示区间，单节显示单节", () => {
    expect(sectionRangeLabel(1, 2)).toBe("第1-2节");
    expect(sectionRangeLabel(6, 6)).toBe("第6节");
    expect(sectionRangeLabel(11, 13)).toBe("第11-13节");
  });

  it("缺节次信息（考试等）或区间倒置返回空串", () => {
    expect(sectionRangeLabel(undefined, undefined)).toBe("");
    expect(sectionRangeLabel(3, undefined)).toBe("");
    expect(sectionRangeLabel(5, 2)).toBe("");
  });
});
