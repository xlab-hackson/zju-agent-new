import { describe, expect, it } from "vitest";
import {
  htmlToText,
  normalizeDate,
  parseSztzResponse,
  parseZdbkResponse,
  toBeijingDate,
} from "./index.js";

/**
 * 样本取自「浙大网页抓包」项目离线 fixtures（tests/fixtures/sztz_tzgg.json、
 * zdbk_login_news.json）的真实字段形态，仅截断正文长度。
 */
const SZTZ_PAYLOAD = {
  code: 0,
  msg: "success",
  extend: {},
  data: [
    {
      id: 19,
      mc: "关于2025-2026学年春夏学期第二、三课堂项目第三次审核时间的通知",
      sfqy: true,
      fbr: "STS261/画不成",
      fbsj: "2026-07-06T07:09:17.000+00:00",
      fjmc: "",
      fjid: "",
      nr: '<p style="text-align: justify;">各院级团委、直属团总支：</p><p>现就审核时间通知如下。</p><p>一、 院级审核时间</p>',
    },
    {
      id: 16,
      mc: "   本科生就业实习记点申请流程（更新）  ",
      sfqy: true,
      fbr: "admin/超管",
      fbsj: "2025-12-29T03:49:15.000+00:00",
      fjmc: null,
      fjid: null,
      nr: "<p>就业实习实践是指学生为提升社会阅历、积累工作经验、拓展综合素质，到企业或事业单位进行就业实习的实践活动。</p>",
    },
    { id: 20, mc: "   ", fbsj: "2026-08-01T00:00:00.000+00:00", nr: "" },
  ],
};

const ZDBK_PAYLOAD = {
  currentPage: 1,
  totalPage: 37,
  totalResult: 547,
  items: [
    {
      fbr: "0912110",
      fbsj: "2026-09-03 17:06:22",
      gglb: "1",
      jgpxzd: "1",
      listnav: "false",
      localeKey: "zh_CN",
      pageable: true,
      queryModel: { currentPage: 1, showCount: 10, totalCount: 0 },
      row_id: "1",
      sfzd: "1",
      totalResult: "547",
      xwbh: "593B769FC1E44784E06329B3CA0A6BEB",
      xwbt: "公共管理学院关于26年冬学期开设海外教师主导全英文课程的选课通知--《...",
      xwfbr: "温小燕",
      yxxwgl: "0",
    },
    {
      fbr: "0013364",
      fbsj: "2026-09-01 09:19:52",
      gglb: "0",
      sfzd: "0",
      xwbh: "ABCDEF0123456789ABCDEF0123456789",
      xwbt: "关于2026年中秋节、国庆节放假安排的通知",
      xwfbr: "教务处",
    },
  ],
};

describe("parseSztzResponse", () => {
  it("解析字段并转北京时间日期", () => {
    const items = parseSztzResponse(SZTZ_PAYLOAD, 15);
    expect(items).toHaveLength(2);
    const first = items[0]!;
    expect(first.source).toBe("sztz");
    expect(first.sourceName).toBe("素质拓展平台");
    expect(first.title).toBe(
      "关于2025-2026学年春夏学期第二、三课堂项目第三次审核时间的通知",
    );
    // UTC 07:09 + 8h = 北京时间 15:09，同日
    expect(first.date).toBe("2026-07-06");
    expect(first.publisher).toBe("STS261/画不成");
    expect(first.url).toBe(
      "https://sztz.zju.edu.cn/dekt/#/index/tzgg?id=19",
    );
    expect(first.summary).toBe(
      "各院级团委、直属团总支： 现就审核时间通知如下。 一、 院级审核时间",
    );
    expect(first.important).toBeUndefined();
  });

  it("UTC 深夜时间跨日进位到北京时间的次日", () => {
    const items = parseSztzResponse(
      {
        code: 0,
        data: [
          { id: 1, mc: "跨日", fbsj: "2026-07-06T17:30:00.000+00:00", nr: "" },
        ],
      },
      15,
    );
    expect(items[0]!.date).toBe("2026-07-07");
  });

  it("标题 trim，无标题记录跳过", () => {
    const items = parseSztzResponse(SZTZ_PAYLOAD, 15);
    expect(items[1]!.title).toBe("本科生就业实习记点申请流程（更新）");
  });

  it("code 非 0 抛 AppError", () => {
    expect(() =>
      parseSztzResponse({ code: 500, msg: "error", data: [] }, 15),
    ).toThrow();
  });

  it("data 缺失返回空数组", () => {
    expect(parseSztzResponse({}, 15)).toEqual([]);
  });

  it("limit 截断", () => {
    const items = parseSztzResponse(SZTZ_PAYLOAD, 1);
    expect(items).toHaveLength(1);
  });
});

describe("parseZdbkResponse", () => {
  it("解析字段、置顶标记与详情链接", () => {
    const items = parseZdbkResponse(ZDBK_PAYLOAD, 15);
    expect(items).toHaveLength(2);
    const first = items[0]!;
    expect(first.source).toBe("zdbk");
    expect(first.sourceName).toBe("教务系统");
    expect(first.title).toBe(
      "公共管理学院关于26年冬学期开设海外教师主导全英文课程的选课通知--《...",
    );
    expect(first.date).toBe("2026-09-03");
    expect(first.publisher).toBe("温小燕");
    expect(first.important).toBe(true);
    expect(first.url).toBe(
      "https://zdbk.zju.edu.cn/jwglxt/xtgl/xwck_ckLoginNews.html?xwbh=593B769FC1E44784E06329B3CA0A6BEB",
    );
    expect(first.summary).toBeUndefined();
  });

  it("非置顶条目 important 为 undefined", () => {
    const items = parseZdbkResponse(ZDBK_PAYLOAD, 15);
    expect(items[1]!.important).toBeUndefined();
  });

  it("items 缺失返回空数组", () => {
    expect(parseZdbkResponse({ totalResult: 0 }, 15)).toEqual([]);
  });
});

describe("toBeijingDate", () => {
  it("UTC ISO 转 +8", () => {
    expect(toBeijingDate("2026-07-06T07:09:17.000+00:00")).toBe("2026-07-06");
    expect(toBeijingDate("2026-07-06T17:30:00.000+00:00")).toBe("2026-07-07");
  });

  it("无时区后缀按北京时间", () => {
    expect(toBeijingDate("2026-07-06T07:09:17.000")).toBe("2026-07-06");
  });

  it("非法输入返回空串", () => {
    expect(toBeijingDate("")).toBe("");
    expect(toBeijingDate("not-a-date")).toBe("");
  });
});

describe("normalizeDate", () => {
  it("教务时间字符串取前 10 位", () => {
    expect(normalizeDate("2026-09-03 17:06:22")).toBe("2026-09-03");
  });

  it("格式不符返回空串", () => {
    expect(normalizeDate("")).toBe("");
    expect(normalizeDate("2026/09/03")).toBe("");
  });
});

describe("htmlToText", () => {
  it("剥标签压缩空白并解码实体", () => {
    expect(
      htmlToText("<p>你好&nbsp;</p><p>  世界 &amp; 再见</p>"),
    ).toBe("你好 世界 & 再见");
  });

  it("截断到指定长度", () => {
    expect(htmlToText("<p>abcdefghij</p>", 5)).toBe("abcde");
  });
});
