import { describe, expect, it } from "vitest";
import { compressWeeks } from "../utils/timetable.js";

describe("compressWeeks", () => {
  it("空数组返回空串", () => {
    expect(compressWeeks([])).toBe("");
  });

  it("单周", () => {
    expect(compressWeeks([5])).toBe("5");
  });

  it("连续区间压缩", () => {
    expect(compressWeeks([1, 2, 3, 4, 5])).toBe("1-5");
  });

  it("多个区间用逗号连接", () => {
    expect(compressWeeks([1, 2, 3, 8, 9, 16])).toBe("1-3,8-9,16");
  });

  it("乱序输入自动排序", () => {
    expect(compressWeeks([9, 1, 2, 8])).toBe("1-2,8-9");
  });

  it("重复周次去重", () => {
    expect(compressWeeks([1, 1, 2, 2, 3])).toBe("1-3");
  });

  it("单双周间隔模式", () => {
    expect(compressWeeks([1, 3, 5, 7, 9])).toBe("1,3,5,7,9");
  });
});
