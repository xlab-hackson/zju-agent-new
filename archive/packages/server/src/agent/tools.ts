/**
 * 工具注册表。
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 9.2 / 9.3 节。
 *
 * 工具分两类：
 * - 查询类（read）：直接执行，无需确认
 * - 操作类（write/payment/external_download）：执行前需用户确认（PendingConfirmation 流）
 *
 * 工具的 execute 只在后端调用，前端不直接执行。
 * 工具依赖运行时服务（auth / zju 适配器 / 缓存等），通过 ToolDeps 注入。
 */

import type {
  AgentTool,
  ToolResult,
  ToolContext,
  Course,
  TimetableEntry,
  Exam,
  Assignment,
  NoticeFetchResult,
} from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";
import { logger } from "../config/logger.js";
import { readGuideDoc, searchGuide } from "../knowledge/index.js";
import { NOTICES_CACHE_KEY, NOTICES_CACHE_TTL_MS } from "../routes/notices.js";

export type ToolDeps = ServicesContainer & { config: ServerConfig };

/** 解析当前已配置的学号（绝不调用学在浙大接口） */
async function resolveStuId(deps: ToolDeps): Promise<string> {
  const cred = await deps.auth.getCredential();
  return cred?.username ?? "";
}

/** 工厂：构建工具实例。依赖运行时服务，故每次请求构建一次。 */
export function buildTools(deps: ToolDeps): AgentTool[] {
  return [
    makeGetUpcomingSchedule(deps),
    makeGetDailySchedule(deps),
    makeGetCourses(deps),
    makeGetAssignments(deps),
    makeGetCourseMaterials(deps),
    makeGetQuizzes(deps),
    makeGetExams(deps),
    makeGetTimetable(deps),
    makeGetGrades(deps),
    makeGetNotices(deps),
    makeSearchGuide(),
    makeReadGuide(),
    makeDownloadCourseMaterial(deps),
    makeBatchDownload(deps),
  ];
}

// ---------- 查询类工具 ----------

function makeGetCourses(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_courses",
    description:
      "查询课程列表（学在浙大）。返回课程 id、名称、学期、教学班。不返回学分/成绩。默认返回所有学期。仅用于查课件或下载时获取课程 id，查课表用 zju_get_timetable，查学分成绩用 zju_get_grades。",
    inputSchema: {
      type: "object",
      properties: {
        semester: {
          type: "string",
          description: "可选，教务网学期 id，如 \"2024-2025-2\"。不传则返回所有学期课程。",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const semesterId = (input as { semester?: string } | null)?.semester;
        const cached = deps.cache.get("courses:list");
        if (cached) return semesterId ? filterBySemester(cached as Course[], semesterId) : cached;
        const adapters = await deps.auth.getServiceAdapters();
        const courses = await adapters.courses.getCourses();
        deps.cache.set("courses:list", courses);
        return semesterId ? filterBySemester(courses, semesterId) : courses;
      });
    },
  };
}

function makeGetAssignments(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_assignments",
    description:
      "查询待办作业（学在浙大）。聚合所有课程未关闭的作业，按截止时间升序。用户问“我最近有什么作业”“哪些作业快到期”时调用。",
    inputSchema: {
      type: "object",
      properties: {
        onlyPending: {
          type: "boolean",
          description: "是否只返回未提交作业，默认 true",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const onlyPending =
          (input as { onlyPending?: boolean } | null)?.onlyPending ?? true;
        const cached = deps.cache.get<unknown[]>("courses:assignments:all");
        let all = cached;
        if (!all) {
          const adapters = await deps.auth.getServiceAdapters();
          const courses = await adapters.courses.getCourses();
          deps.cache.set("courses:list", courses);
          const list: unknown[] = [];
          for (const c of courses) {
            try {
              const a = await adapters.courses.getAssignments(c.id, c.name);
              deps.cache.set(`courses:assignments:${c.id}`, a);
              list.push(...a);
            } catch (err) {
              logger.warn("工具获取作业失败", {
                courseId: c.id,
                message: err instanceof Error ? err.message : String(err),
              });
            }
          }
          deps.cache.set("courses:assignments:all", list, 10 * 60_000);
          all = list;
        }
        const filtered = onlyPending
          ? (all as Array<{ submitted?: boolean }>).filter((a) => !a.submitted)
          : all;
        return filtered;
      });
    },
  };
}

function makeGetCourseMaterials(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_course_materials",
    description:
      "查询某门课程的资料列表（学在浙大）。返回资料条目与可下载文件。用户问“某课有哪些课件”时调用。",
    inputSchema: {
      type: "object",
      properties: {
        courseId: { type: "string", description: "课程 id" },
      },
      required: ["courseId"],
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const courseId = (input as { courseId?: string } | null)?.courseId;
        if (!courseId) {
          return { ok: false, error: { code: "TOOL_INPUT_INVALID", message: "缺少 courseId" } };
        }
        const adapters = await deps.auth.getServiceAdapters();
        return adapters.courses.getMaterials(courseId);
      });
    },
  };
}

function makeGetQuizzes(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_quizzes",
    description:
      "查询某门课程的在线测试/小测列表（学在浙大）。注意这是课程内的在线测验，不是教务网期末考试安排。用户问“某课有没有小测”“在线测试”时调用。",
    inputSchema: {
      type: "object",
      properties: {
        courseId: { type: "string", description: "课程 id" },
      },
      required: ["courseId"],
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const courseId = (input as { courseId?: string } | null)?.courseId;
        if (!courseId) {
          return { ok: false, error: { code: "TOOL_INPUT_INVALID", message: "缺少 courseId" } };
        }
        const adapters = await deps.auth.getServiceAdapters();
        // 用课程名而非 id 作为 courseName，提升可读性
        let courseName = courseId;
        let courses = deps.cache.get<Course[]>("courses:list");
        if (!courses) {
          courses = await adapters.courses.getCourses();
          deps.cache.set("courses:list", courses);
        }
        const found = courses.find((c) => c.id === courseId);
        if (found) courseName = found.name;
        return adapters.courses.getQuizzes(courseId, courseName);
      });
    },
  };
}

function makeGetUpcomingSchedule(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_upcoming_schedule",
    description:
      "查询接下来48小时内的实时校园日程流（包含正在进行或即将开始的课程与考试，以及48小时内即将截止的作业待办）。仿照 Celechron 体系构建，自带精准倒计时、地点、教师、作业截止时间。当用户询问“接下来有什么课/安排”“今天/明天接下来做什么”“未来48小时安排”“最近有什么作业快截止了”“现在正在上什么课”时优先调用本工具。",
    inputSchema: {
      type: "object",
      properties: {
        semester: {
          type: "string",
          description: "可选，教务网学期 id（如 \"2026-2027-1\"）。不传自动根据公历推算当前学期。",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const stuId = await resolveStuId(deps);
        const reqSemester = (input as { semester?: string } | null)?.semester;
        const targetSem = reqSemester ?? deps.calendar.getCurrentSemesterId();

        // 1. 获取课表（缓存优先）
        const ttKey = `zdbk:timetable:${targetSem}`;
        let entries = deps.cache.get<TimetableEntry[]>(ttKey);
        const adapters = await deps.auth.getServiceAdapters();
        if (!entries) {
          try {
            entries = await adapters.zdbk.getTimetable(stuId, targetSem);
            deps.cache.set(ttKey, entries);
          } catch {
            entries = [];
          }
        }

        // 2. 获取考试（缓存优先）
        const examKey = `zdbk:exams:${targetSem}`;
        let exams = deps.cache.get<Exam[]>(examKey);
        if (!exams) {
          try {
            exams = await adapters.zdbk.getExams(stuId, [targetSem]);
            deps.cache.set(examKey, exams);
          } catch {
            exams = [];
          }
        }

        // 3. 关联待办作业
        let assignments = deps.cache.get<Assignment[]>("courses:assignments:all");
        if (!assignments) {
          try {
            const courses = await adapters.courses.getCourses();
            const all: Assignment[] = [];
            for (const c of courses) {
              try {
                const list = await adapters.courses.getAssignments(c.id, c.name);
                all.push(...list);
              } catch {
                // ignore
              }
            }
            deps.cache.set("courses:assignments:all", all, 10 * 60_000);
            assignments = all;
          } catch {
            assignments = [];
          }
        }

        return await deps.calendar.getUpcomingSchedule48h({
          timetableEntries: entries ?? [],
          exams: exams ?? [],
          assignments: assignments ?? [],
          semesterId: targetSem,
        });
      });
    },
  };
}

function makeGetDailySchedule(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_daily_schedule",
    description:
      "查询某一日的综合校园日程（包含当天实际上的课程、当天的考试、当天到期的作业）。自动结合浙大校历计算教学周次、是否放假、是否调休补课。当用户问“今天有什么安排”“明天日程”“周三有什么事”“今天放假吗”时优先调用本工具。",
    inputSchema: {
      type: "object",
      properties: {
        date: {
          type: "string",
          description: "可选，日期描述，支持 \"today\"（今天）、\"tomorrow\"（明天）、\"yesterday\"（昨天）或 \"YYYY-MM-DD\"。不传默认 \"today\"。",
        },
        semester: {
          type: "string",
          description: "可选，教务网学期 id（如 \"2026-2027-1\"）。不传自动根据公历推算当前学期。",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const stuId = await resolveStuId(deps);
        const reqDate = (input as { date?: string } | null)?.date ?? "today";
        const reqSemester = (input as { semester?: string } | null)?.semester;
        const targetSem = reqSemester ?? deps.calendar.getCurrentSemesterId();

        // 1. 获取课表（缓存优先）
        const ttKey = `zdbk:timetable:${targetSem}`;
        let entries = deps.cache.get<TimetableEntry[]>(ttKey);
        const adapters = await deps.auth.getServiceAdapters();
        if (!entries) {
          try {
            entries = await adapters.zdbk.getTimetable(stuId, targetSem);
            deps.cache.set(ttKey, entries);
          } catch {
            entries = [];
          }
        }

        // 2. 获取考试（缓存优先）
        const examKey = `zdbk:exams:${targetSem}`;
        let exams = deps.cache.get<Exam[]>(examKey);
        if (!exams) {
          try {
            exams = await adapters.zdbk.getExams(stuId, [targetSem]);
            deps.cache.set(examKey, exams);
          } catch {
            exams = [];
          }
        }

        // 3. 关联待办作业
        const assignments = deps.cache.get<Assignment[]>("courses:assignments:all") ?? [];

        return await deps.calendar.getDailySchedule({
          timetableEntries: entries ?? [],
          exams: exams ?? [],
          assignments,
          date: reqDate,
          semesterId: targetSem,
        });
      });
    },
  };
}

function makeGetExams(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_exams",
    description:
      "查询考试安排（教务网）。返回期末与期中考试，含时间、地点、座位号，按时间升序。默认返回当前学期，也可通过 semester 指定学期（格式 \"2026-2027-1\"=秋冬）。用户问“我有什么考试”“考试安排”“上学期考了什么”时调用。",
    inputSchema: {
      type: "object",
      properties: {
        semester: {
          type: "string",
          description: "可选，教务网学期 id，如 \"2026-2027-1\"。不传自动取当前学期。",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const stuId = await resolveStuId(deps);
        const reqSemester = (input as { semester?: string } | null)?.semester;
        const target = reqSemester ?? deps.calendar.getCurrentSemesterId();
        if (!target) return [];
        const cacheKey = `zdbk:exams:${target}`;
        const cached = deps.cache.get(cacheKey);
        if (cached) return cached;
        const adapters = await deps.auth.getServiceAdapters();
        const exams = await adapters.zdbk.getExams(stuId, [target]);
        deps.cache.set(cacheKey, exams);
        return exams;
      });
    },
  };
}

function makeGetTimetable(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_timetable",
    description:
      "查询课程表（教务网）。返回课表条目（含课程名、教师、地点、星期、节次、周次）。支持传入 date 查询某天真实课表（自动按校历剔除假期并处理调休换日）。用户问“我有什么课”“明天有什么课”“今天下午有什么课”时调用。",
    inputSchema: {
      type: "object",
      properties: {
        date: {
          type: "string",
          description: "可选，具体日期或相对时间：\"today\"（今天）、\"tomorrow\"（明天）或 \"YYYY-MM-DD\"。指定时将按浙大校历计算当天真实课程（自动处理法定节假日与调休补课）。",
        },
        semester: {
          type: "string",
          description: "可选，教务网学期 id，如 \"2026-2027-1\"。不传自动取当前学期。",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const stuId = await resolveStuId(deps);
        const reqSemester = (input as { semester?: string } | null)?.semester;
        const targetSem = reqSemester ?? deps.calendar.getCurrentSemesterId();
        if (!targetSem) return [];
        const cacheKey = `zdbk:timetable:${targetSem}`;
        let entries = deps.cache.get<TimetableEntry[]>(cacheKey);
        if (!entries) {
          const adapters = await deps.auth.getServiceAdapters();
          entries = await adapters.zdbk.getTimetable(stuId, targetSem);
          deps.cache.set(cacheKey, entries);
        }

        const reqDate = (input as { date?: string } | null)?.date;
        if (reqDate) {
          const daily = await deps.calendar.getDailySchedule({
            timetableEntries: entries ?? [],
            date: reqDate,
            semesterId: targetSem,
          });
          return {
            date: daily.date,
            dateInfo: daily.dateInfo,
            summary: daily.summary,
            classes: daily.events.filter((e) => e.type === "class"),
          };
        }

        return entries;
      });
    },
  };
}

function makeGetNotices(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_notices",
    description:
      "查询学校最近发布的通知公告（素质拓展平台 + 教务系统，公开源无需登录）。返回标题、发布日期、来源、发布人、置顶标记与详情链接。用户问「最近有什么学校通知/公告」「素拓有什么通知」时调用。",
    inputSchema: {
      type: "object",
      properties: {
        source: {
          type: "string",
          enum: ["sztz", "zdbk"],
          description:
            "可选，按来源过滤：sztz=素质拓展平台，zdbk=教务系统。不传返回全部。",
        },
        limit: {
          type: "number",
          description: "可选，返回条数上限，默认 15，最大 50。",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const q = (input ?? {}) as { source?: string; limit?: number };
        let result = deps.cache.get<NoticeFetchResult>(NOTICES_CACHE_KEY);
        if (!result) {
          result = await deps.notices.getAllNotices(15);
          deps.cache.set(NOTICES_CACHE_KEY, result, NOTICES_CACHE_TTL_MS);
        }
        let items = result.items;
        if (q.source === "sztz" || q.source === "zdbk") {
          items = items.filter((n) => n.source === q.source);
        }
        const limit =
          typeof q.limit === "number" && q.limit > 0
            ? Math.min(Math.floor(q.limit), 50)
            : 15;
        return { items: items.slice(0, limit), failures: result.failures };
      });
    },
  };
}

function makeGetGrades(deps: ToolDeps): AgentTool {
  return {
    name: "zju_get_grades",
    description:
      "查询成绩和学分（教务网）。返回每门课的原始成绩、学分(credit)、五分制绩点(fivePoint)。这是唯一能查到学分的接口，zju_get_courses 不返回学分。默认返回所有学期。用户问'学分''绩点''成绩''GPA'时必须调本工具。",
    inputSchema: {
      type: "object",
      properties: {
        semester: {
          type: "string",
          description: "可选，教务网学期 id。不传则返回所有学期成绩。",
        },
      },
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const stuId = await resolveStuId(deps);
        const target = (input as { semester?: string } | null)?.semester ?? "";
        const cacheKey = `zdbk:grades:${target}`;
        const cached = deps.cache.get(cacheKey);
        if (cached) return cached;
        const adapters = await deps.auth.getServiceAdapters();
        const grades = await adapters.zdbk.getGrades(stuId, target);
        deps.cache.set(cacheKey, grades);
        return grades;
      });
    },
  };
}

// ---------- 校园常识知识库（只读，无需登录） ----------

/** 知识库出处与免责说明，随检索结果一起回喂给模型 */
const GUIDE_SOURCE_NOTE =
  "内容摘自 CC98《浙江大学本科新生指引》（非官方，仅供参考；政策类信息以学校官方最新通知为准）";

function makeSearchGuide(): AgentTool {
  return {
    name: "zju_search_guide",
    description:
      "检索浙大校园常识知识库（CC98《浙江大学本科新生指引》，非官方）。涵盖选课规则与抽签机制、课程考核与绩点、奖助学金与荣誉称号、专业确认与转专业、培养方案与辅修、宿舍园区、校园网与校园卡、图书馆、就医医保、快递、军训、社团、常用网站等制度与生活常识。用户问这类「浙大怎么规定/怎么办」的问题时先调本工具，再依据返回的原文回答。查个人实时数据（课程/作业/考试/课表/成绩）用 zju_get_* 系列工具，不要用本工具。",
    inputSchema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description:
            "检索关键词或用户问题，如「绩点怎么算」「选课抽签规则」「医保怎么报销」。",
        },
        limit: {
          type: "number",
          description: "可选，返回片段条数上限，默认 4，最大 6。",
        },
      },
      required: ["query"],
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const q = (input ?? {}) as { query?: string; limit?: number };
        const query = q.query?.trim() ?? "";
        if (!query) {
          return { results: [], hint: "缺少 query 参数。" };
        }
        const limit =
          typeof q.limit === "number" && q.limit > 0
            ? Math.min(Math.floor(q.limit), 6)
            : 4;
        const results = searchGuide(query, limit);
        if (results.length === 0) {
          return {
            results: [],
            hint: "知识库中没有找到相关内容。请如实告知用户指引里没有，不要编造浙大规定；可以换更短的关键词再试一次。",
          };
        }
        return { results, source: GUIDE_SOURCE_NOTE };
      });
    },
  };
}

function makeReadGuide(): AgentTool {
  return {
    name: "zju_read_guide",
    description:
      "读取知识库中某篇文档的全文。先用 zju_search_guide 检索；当返回的片段被截断、或需要完整上下文（例如整章选课规则）时，用本工具按 doc 路径读取全文（超长会再次截断）。",
    inputSchema: {
      type: "object",
      properties: {
        doc: {
          type: "string",
          description:
            "文档路径，如 \"course_sys/rules.md\"，取自 zju_search_guide 结果里的 doc 字段。",
        },
      },
      required: ["doc"],
      additionalProperties: false,
    },
    riskLevel: "read",
    requiresConfirmation: false,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const q = (input ?? {}) as { doc?: string };
        const doc = q.doc?.trim() ?? "";
        if (!doc) return { hint: "缺少 doc 参数。" };
        return readGuideDoc(doc);
      });
    },
  };
}

// ---------- 操作类工具（高风险，需确认） ----------
/**
 * 下载课程资料。
 * 风险等级 external_download；单文件下载默认不需确认（见 settings.confirmSingleDownload），
 * 但 Agent 路径强制走确认流，避免静默落盘。
 * 实际执行由 confirm 流触发后调用本函数。
 */
export function makeDownloadCourseMaterial(deps: ToolDeps): AgentTool {
  return {
    name: "zju_download_course_material",
    description:
      "下载单个课程资料文件到本地。需 courseId、fileId（upload id 非 referenceId）、fileName。仅用于下载 1-2 个文件；如需批量下载多个文件，请用 zju_batch_download 一次性提交，避免逐个确认。",
    inputSchema: {
      type: "object",
      properties: {
        courseId: { type: "string" },
        materialId: { type: "string" },
        fileId: {
          type: "string",
          description: "文件的 upload id（CourseFile.id），用于 /api/uploads/{id}/blob",
        },
        fileName: { type: "string", description: "保存的文件名" },
        officePdf: {
          type: "boolean",
          description: "Office 文件(.docx/.pptx/.xlsx)是否取 PDF 预览版，默认 false",
        },
      },
      required: ["courseId", "fileId", "fileName"],
      additionalProperties: false,
    },
    riskLevel: "external_download",
    requiresConfirmation: true,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const body = input as {
          courseId: string;
          materialId?: string;
          fileId: string;
          fileName: string;
          officePdf?: boolean;
        };
        if (!body.fileId || !body.fileName) {
          return {
            ok: false,
            error: { code: "TOOL_INPUT_INVALID", message: "缺少 fileId 或 fileName" },
          };
        }
        const adapters = await deps.auth.getServiceAdapters();
        const { writeDownloadStream } = await import("../util/download.js");
        const safeName = sanitizeFileName(body.fileName);
        const subdir = sanitizeDir(body.materialId || body.courseId);
        const result = await writeDownloadStream({
          stream: async () => {
            const file = await adapters.courses.fetchFile(body.fileId, {
              officePdf: body.officePdf,
            });
            return file.stream;
          },
          downloadDir: deps.config.downloadDir,
          subdir,
          fileName: safeName,
        });
        const record = deps.downloads.create({
          source: "courses",
          fileName: result.fileName,
          filePath: result.filePath,
          status: "completed",
          size: result.size,
          mimeType: result.contentType,
          courseId: body.courseId,
          materialId: body.materialId,
          fileId: body.fileId,
        });
        deps.audit.log({
          action: "download",
          riskLevel: "external_download",
          inputSummary: `agent/${body.courseId}/${body.fileId}/${safeName}`,
          confirmed: true,
          result: "ok",
        });
        return {
          id: record.id,
          fileName: record.fileName,
          filePath: record.filePath,
          size: record.size,
        };
      });
    },
  };
}

/**
 * 批量下载课程资料。一次确认即可下载多个文件，无需逐个确认。
 * 每个文件独立下载，单个失败不影响其他文件。
 */
function makeBatchDownload(deps: ToolDeps): AgentTool {
  return {
    name: "zju_batch_download",
    description:
      "批量下载多个课程资料文件到本地。一次确认即可完成全部下载，无需逐个确认。用户说【下载所有课件】【把这门课的资料都下载下来】时优先使用本工具。每个文件需 courseId、fileId（upload id 非 referenceId）、fileName。",
    inputSchema: {
      type: "object",
      properties: {
        files: {
          type: "array",
          description: "要下载的文件列表",
          items: {
            type: "object",
            properties: {
              courseId: { type: "string" },
              materialId: { type: "string" },
              fileId: { type: "string", description: "文件的 upload id（CourseFile.id），非 referenceId" },
              fileName: { type: "string", description: "保存的文件名" },
              officePdf: { type: "boolean", description: "Office 文件是否取 PDF 预览版，默认 false" },
            },
            required: ["courseId", "fileId", "fileName"],
            additionalProperties: false,
          },
          minItems: 1,
          maxItems: 50,
        },
      },
      required: ["files"],
      additionalProperties: false,
    },
    riskLevel: "external_download",
    requiresConfirmation: true,
    async execute(input, ctx): Promise<ToolResult> {
      return runRead(ctx, async () => {
        const body = input as {
          files: Array<{
            courseId: string;
            materialId?: string;
            fileId: string;
            fileName: string;
            officePdf?: boolean;
          }>;
        };
        if (!body.files || body.files.length === 0) {
          return {
            ok: false,
            error: { code: "TOOL_INPUT_INVALID", message: "files 数组不能为空" },
          };
        }
        const adapters = await deps.auth.getServiceAdapters();
        const { writeDownloadStream } = await import("../util/download.js");

        const results: Array<{
          fileId: string;
          fileName: string;
          success: boolean;
          filePath?: string;
          size?: number;
          error?: string;
        }> = [];

        for (const f of body.files) {
          try {
            const safeName = sanitizeFileName(f.fileName);
            const subdir = sanitizeDir(f.materialId || f.courseId);
            const streamResult = await writeDownloadStream({
              stream: async () => {
                const file = await adapters.courses.fetchFile(f.fileId, {
                  officePdf: f.officePdf,
                });
                return file.stream;
              },
              downloadDir: deps.config.downloadDir,
              subdir,
              fileName: safeName,
            });
            const record = deps.downloads.create({
              source: "courses",
              fileName: streamResult.fileName,
              filePath: streamResult.filePath,
              status: "completed",
              size: streamResult.size,
              mimeType: streamResult.contentType,
              courseId: f.courseId,
              materialId: f.materialId,
              fileId: f.fileId,
            });
            deps.audit.log({
              action: "download",
              riskLevel: "external_download",
              inputSummary: `batch/${f.courseId}/${f.fileId}/${safeName}`,
              confirmed: true,
              result: "ok",
            });
            results.push({
              fileId: f.fileId,
              fileName: safeName,
              success: true,
              filePath: record.filePath,
              size: record.size,
            });
          } catch (err) {
            const message = err instanceof Error ? err.message : String(err);
            logger.warn("批量下载单文件失败", { fileId: f.fileId, fileName: f.fileName, message });
            results.push({
              fileId: f.fileId,
              fileName: f.fileName,
              success: false,
              error: message,
            });
          }
        }

        const succeeded = results.filter((r) => r.success).length;
        const failed = results.filter((r) => !r.success).length;
        return {
          summary: `批量下载完成：${succeeded} 成功，${failed} 失败`,
          results,
        };
      });
    },
  };
}

// ---------- 辅助 ----------

/** 按学期过滤课程（学期 id 后缀 "-2" 映射春夏学期） */
function filterBySemester(courses: Course[], semesterId: string): Course[] {
  // 学在浙大学期 id 形如 "xxx2024-2025-2xxx" 或 "xxx2024-2025-1xxx"
  // 教务网格式 "2024-2025-2"
  const [year, term] = semesterId.split("-").filter(Boolean);
  // 构建可能的学在浙大学期 id 前缀匹配
  return courses.filter((c) => {
    const sid = c.semesterId;
    // 教务网 "2024-2025-2" → 学在浙大可能包含 "2024-2025" 和第2学期特征
    return (
      sid.includes(`${year}-${Number(year) + 1}`) &&
      (term === "2" ? /春|夏/.test(sid) || sid.endsWith("-2") : /秋|冬|短/.test(sid) || sid.endsWith("-1"))
    );
  });
}

/** 包裹读取类工具的执行：把 AppError 转 ToolResult，日志脱敏 */
async function runRead(
  _ctx: ToolContext,
  fn: () => Promise<unknown>,
): Promise<ToolResult> {
  try {
    const data = await fn();
    return { ok: true, data };
  } catch (err) {
    const code =
      err && typeof err === "object" && "code" in err
        ? String((err as { code: unknown }).code)
        : "UNKNOWN_ERROR";
    const message =
      err instanceof Error ? err.message : "工具执行失败";
    logger.warn("工具执行失败", { code, message });
    return { ok: false, error: { code, message } };
  }
}

function sanitizeFileName(name: string): string {
  const base = name.replace(/[/\\]/g, "_").replace(/\.\.+/g, ".").trim();
  const safe = base.replace(/[<>:"|?* ]/g, "_");
  return safe.slice(0, 180) || `file-${Date.now()}`;
}

function sanitizeDir(name: string): string {
  const safe = sanitizeFileName(name);
  return safe.slice(0, 80) || "misc";
}
