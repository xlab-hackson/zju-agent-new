/**
 * 教务网 (zdbk.zju.edu.cn) 路由：考试安排 + 课程表 + 成绩 + 综合日程。
 * 彻底摒弃依赖学在浙大 (courses) 推算学期与时间的逻辑，全面采用 CalendarService。
 *
 * 路由：
 *   GET /api/zju/academic-date — 当前教学周/节假日/调休详情
 *   GET /api/zju/schedule      — 某日综合日程（课表投影 + 考试 + 作业）
 *   GET /api/zju/exams         — 考试安排（默认当前学期，无需经过 courses）
 *   GET /api/zju/timetable     — 课程表（默认当前学期，无需经过 courses）
 *   GET /api/zju/grades        — 成绩（可指定 xnxq01id）
 */

import type { FastifyPluginAsync } from "fastify";
import {
  wrap,
  AppError,
  ErrorCode,
  type Exam,
  type TimetableEntry,
  type Grade,
  type Assignment,
  mergeTimetableEntries,
} from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";

const CACHE_KEYS = {
  exams: (xnxq: string) => `zdbk:exams:${xnxq}`,
  timetable: (xnxq: string) => `zdbk:timetable:${xnxq}`,
  grades: (xnxq: string) => `zdbk:grades:${xnxq}`,
} as const;

export function zdbkRoutes(
  deps: ServicesContainer & { config: ServerConfig },
): FastifyPluginAsync {
  return async (app) => {
    // --- 当前教学日期与周次信息 ---
    app.get<{
      Querystring: { date?: string };
    }>("/academic-date", async (req) => {
      return wrap(async () => {
        const date = req.query.date ? new Date(req.query.date) : new Date();
        return await deps.calendar.getDateInfo(date);
      });
    });

    // --- 综合日程（课表投影到真实公历日 + 当天考试 + 当天截止作业） ---
    app.get<{
      Querystring: { date?: string; xnxq01id?: string };
    }>("/schedule", async (req) => {
      return wrap(async () => {
        const stuId = await resolveStu(deps);
        const target = req.query.xnxq01id ?? deps.calendar.getCurrentSemesterId();
        const dateStr = req.query.date ?? "today";

        // 1. 获取课表（缓存优先）
        const ttKey = CACHE_KEYS.timetable(target);
        let entries = deps.cache.get<TimetableEntry[]>(ttKey);
        const adapters = await deps.auth.getServiceAdapters();
        if (!entries) {
          entries = await adapters.zdbk.getTimetable(stuId, target);
          deps.cache.set(ttKey, entries);
        }
        entries = mergeTimetableEntries(entries ?? []);

        // 2. 获取考试（缓存优先，静默容错）
        const examKey = CACHE_KEYS.exams(target);
        let exams = deps.cache.get<Exam[]>(examKey);
        if (!exams) {
          try {
            exams = await adapters.zdbk.getExams(stuId, [target]);
            deps.cache.set(examKey, exams);
          } catch {
            exams = [];
          }
        }

        return await deps.calendar.getDailySchedule({
          timetableEntries: entries ?? [],
          exams: exams ?? [],
          date: dateStr,
          semesterId: target,
        });
      });
    });

    // --- 仿 Celechron 接下来 48 小时日程流与 48 小时内截止作业 ---
    app.get<{
      Querystring: { xnxq01id?: string };
    }>("/schedule/upcoming-48h", async (req) => {
      return wrap(async () => {
        const stuId = await resolveStu(deps);
        const target = req.query.xnxq01id ?? deps.calendar.getCurrentSemesterId();

        // 1. 获取课表（缓存优先）
        const ttKey = CACHE_KEYS.timetable(target);
        let entries = deps.cache.get<TimetableEntry[]>(ttKey);
        const adapters = await deps.auth.getServiceAdapters();
        if (!entries) {
          try {
            entries = await adapters.zdbk.getTimetable(stuId, target);
            deps.cache.set(ttKey, entries);
          } catch {
            entries = [];
          }
        }
        entries = mergeTimetableEntries(entries ?? []);

        // 2. 获取考试（缓存优先，静默容错）
        const examKey = CACHE_KEYS.exams(target);
        let exams = deps.cache.get<Exam[]>(examKey);
        if (!exams) {
          try {
            exams = await adapters.zdbk.getExams(stuId, [target]);
            deps.cache.set(examKey, exams);
          } catch {
            exams = [];
          }
        }

        // 3. 获取待办作业（从缓存或源获取）
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
          semesterId: target,
        });
      });
    });

    // --- 考试安排 ---
    app.get<{
      Querystring: { xnxq01id?: string };
    }>("/exams", async (req) => {
      return wrap(async () => {
        const stuId = await resolveStu(deps);
        const target = req.query.xnxq01id ?? deps.calendar.getCurrentSemesterId();
        const cacheKey = CACHE_KEYS.exams(target);
        const cached = deps.cache.get<Exam[]>(cacheKey);
        if (cached) return cached;
        const adapters = await deps.auth.getServiceAdapters();
        const exams = await adapters.zdbk.getExams(stuId, [target]);
        deps.cache.set(cacheKey, exams);
        return exams;
      });
    });

    // --- 课程表 ---
    app.get<{
      Querystring: { xnxq01id?: string };
    }>("/timetable", async (req) => {
      return wrap(async () => {
        const stuId = await resolveStu(deps);
        const target = req.query.xnxq01id ?? deps.calendar.getCurrentSemesterId();
        const cacheKey = CACHE_KEYS.timetable(target);
        const cached = deps.cache.get<TimetableEntry[]>(cacheKey);
        if (cached) return mergeTimetableEntries(cached);
        const adapters = await deps.auth.getServiceAdapters();
        const entries = mergeTimetableEntries(await adapters.zdbk.getTimetable(stuId, target));
        deps.cache.set(cacheKey, entries);
        return entries;
      });
    });

    // --- 成绩 ---
    app.get<{
      Querystring: { xnxq01id?: string };
    }>("/grades", async (req) => {
      return wrap(async () => {
        const stuId = await resolveStu(deps);
        // 指定学期则过滤，不指定则返回全部
        const target = req.query.xnxq01id ?? "";
        const cacheKey = CACHE_KEYS.grades(target);
        const cached = deps.cache.get<Grade[]>(cacheKey);
        if (cached) return cached;
        const adapters = await deps.auth.getServiceAdapters();
        const grades = await adapters.zdbk.getGrades(stuId, target);
        deps.cache.set(cacheKey, grades);
        return grades;
      });
    });
  };
}

/** 仅解析 stuId（= ZJU 用户名），绝不再调用 courses.getSemesters() */
async function resolveStu(deps: ServicesContainer): Promise<string> {
  const cred = await deps.auth.getCredential();
  if (!cred) {
    throw new AppError(
      ErrorCode.ZJU_CREDENTIAL_MISSING,
      "尚未配置 ZJU 账号，无法访问校园服务。",
      { retryable: false },
    );
  }
  return cred.username;
}
