/**
 * 学在浙大 (courses.zju.edu.cn) 路由。
 * 见 ZJU_CAMPUS_AGENT_PROJECT.md 第 8.1 / 10.3 节。
 *
 * 路由：
 *   GET  /api/zju/semesters
 *   GET  /api/zju/courses
 *   GET  /api/zju/courses/:courseId/materials
 *   GET  /api/zju/courses/:courseId/assignments
 *   GET  /api/zju/courses/:courseId/quizzes
 *   GET  /api/zju/assignments          （聚合所有课程的待办作业）
 *   POST /api/zju/materials/download   （下载资料文件到本地目录）
 *
 * 所有读接口走 CampusCache（带 TTL），失败回源。
 * 下载走流式落盘到 config.downloadDir，记录 audit 与 downloads 表。
 */

import type { FastifyPluginAsync } from "fastify";
import {
  wrap,
  AppError,
  ErrorCode,
  type Semester,
  type Course,
  type CourseMaterial,
  type Assignment,
  type Quiz,
} from "@zju-agent/core";
import type { ServicesContainer } from "../services.js";
import type { ServerConfig } from "../config/env.js";
import { logger } from "../config/logger.js";
import { writeDownloadStream } from "../util/download.js";

const CACHE_KEYS = {
  semesters: "courses:semesters",
  courses: "courses:list",
  materials: (id: string) => `courses:materials:${id}`,
  assignments: (id: string) => `courses:assignments:${id}`,
  quizzes: (id: string) => `courses:quizzes:${id}`,
} as const;

export function zjuCoursesRoutes(
  deps: ServicesContainer & { config: ServerConfig },
): FastifyPluginAsync {
  return async (app) => {
    // --- 学期 ---
    app.get("/semesters", async () => {
      return wrap(async () => {
        const cached = deps.cache.get<Semester[]>(CACHE_KEYS.semesters);
        if (cached) return cached;
        const adapters = await deps.auth.getServiceAdapters();
        const semesters = await adapters.courses.getSemesters();
        deps.cache.set(CACHE_KEYS.semesters, semesters);
        return semesters;
      });
    });

    // --- 课程列表 ---
    app.get("/courses", async () => {
      return wrap(async () => {
        const cached = deps.cache.get<Course[]>(CACHE_KEYS.courses);
        if (cached) return cached;
        const adapters = await deps.auth.getServiceAdapters();
        const courses = await adapters.courses.getCourses();
        deps.cache.set(CACHE_KEYS.courses, courses);
        return courses;
      });
    });

    // --- 课程资料 ---
    app.get<{ Params: { courseId: string } }>(
      "/courses/:courseId/materials",
      async (req) => {
        return wrap(async () => {
          const { courseId } = req.params;
          const cacheKey = CACHE_KEYS.materials(courseId);
          const cached = deps.cache.get<CourseMaterial[]>(cacheKey);
          if (cached) return cached;
          const adapters = await deps.auth.getServiceAdapters();
          const materials = await adapters.courses.getMaterials(courseId);
          deps.cache.set(cacheKey, materials);
          return materials;
        });
      },
    );

    // --- 课程作业 ---
    app.get<{ Params: { courseId: string } }>(
      "/courses/:courseId/assignments",
      async (req) => {
        return wrap(async () => {
          const { courseId } = req.params;
          const cacheKey = CACHE_KEYS.assignments(courseId);
          const cached = deps.cache.get<Assignment[]>(cacheKey);
          if (cached) return cached;
          const [courseName] = await resolveCourseName(deps, courseId);
          const adapters = await deps.auth.getServiceAdapters();
          const assignments = await adapters.courses.getAssignments(
            courseId,
            courseName,
          );
          deps.cache.set(cacheKey, assignments);
          return assignments;
        });
      },
    );

    // --- 课程测试 ---
    app.get<{ Params: { courseId: string } }>(
      "/courses/:courseId/quizzes",
      async (req) => {
        return wrap(async () => {
          const { courseId } = req.params;
          const cacheKey = CACHE_KEYS.quizzes(courseId);
          const cached = deps.cache.get<Quiz[]>(cacheKey);
          if (cached) return cached;
          const [courseName] = await resolveCourseName(deps, courseId);
          const adapters = await deps.auth.getServiceAdapters();
          const quizzes = await adapters.courses.getQuizzes(courseId, courseName);
          deps.cache.set(cacheKey, quizzes);
          return quizzes;
        });
      },
    );

    // --- 聚合作业（所有课程待办） ---
    app.get("/assignments", async () => {
      return wrap(async () => {
        const cached = deps.cache.get<Assignment[]>("courses:assignments:all");
        if (cached) return cached;
        const courses = await deps.auth.getServiceAdapters().then((a) =>
          a.courses.getCourses()
        );
        deps.cache.set(CACHE_KEYS.courses, courses);
        const adapters = await deps.auth.getServiceAdapters();
        const all: Assignment[] = [];
        for (const c of courses) {
          try {
            const list = await adapters.courses.getAssignments(c.id, c.name);
            deps.cache.set(CACHE_KEYS.assignments(c.id), list);
            all.push(...list);
          } catch (err) {
            logger.warn("获取课程作业失败", {
              courseId: c.id,
              message: err instanceof Error ? err.message : String(err),
            });
          }
        }
        // 按截止时间升序，无截止时间靠后
        all.sort((a, b) => {
          const ta = a.deadline ? Date.parse(a.deadline) : NaN;
          const tb = b.deadline ? Date.parse(b.deadline) : NaN;
          if (Number.isNaN(ta) && Number.isNaN(tb)) return 0;
          if (Number.isNaN(ta)) return 1;
          if (Number.isNaN(tb)) return -1;
          return ta - tb;
        });
        deps.cache.set("courses:assignments:all", all, 10 * 60_000);
        return all;
      });
    });

    // --- 下载课程资料 ---
    app.post<{
      Body: {
        courseId: string;
        materialId: string;
        fileId: string;
        fileName: string;
        /** Office 文件是否取预览版（PDF 化）。默认 false */
        officePdf?: boolean;
        /** materialId 命名的子目录，避免重名 */
        subdir?: string;
      };
    }>("/materials/download", async (req) => {
      return wrap(async () => {
        const body = req.body ?? ({} as typeof req.body);
        const { courseId, materialId, fileId, fileName } = body;
        if (!fileId || !fileName) {
          throw new AppError(
            ErrorCode.TOOL_INPUT_INVALID,
            "缺少 fileId 或 fileName。",
          );
        }
        const adapters = await deps.auth.getServiceAdapters();
        const safeName = sanitizeFileName(fileName);
        const subdir = sanitizeDir(body.subdir ?? materialId ?? courseId);
        const result = await writeDownloadStream({
          stream: async () => {
            const file = await adapters.courses.fetchFile(fileId, {
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
          courseId,
          materialId,
          fileId,
        });
        deps.audit.log({
          action: "download",
          riskLevel: "external_download",
          inputSummary: `courses/${courseId}/${fileId}/${safeName}`,
          confirmed: true,
          result: "ok",
        });
        logger.info("课程资料下载完成", {
          courseId,
          fileId,
          fileName: safeName,
          size: result.size,
        });
        return record;
      });
    });
  };
}

/** 从课程缓存/接口解析课程名，用于填充作业/测试的 courseName */
async function resolveCourseName(
  deps: ServicesContainer,
  courseId: string,
): Promise<[string, Course | undefined]> {
  const list = deps.cache.get<Course[]>(CACHE_KEYS.courses);
  const found = list?.find((c) => c.id === courseId);
  if (found) return [found.name, found];
  try {
    const adapters = await deps.auth.getServiceAdapters();
    const fresh = await adapters.courses.getCourses();
    deps.cache.set(CACHE_KEYS.courses, fresh);
    const f = fresh.find((c) => c.id === courseId);
    return [f?.name ?? courseId, f];
  } catch {
    return [courseId, undefined];
  }
}

/** 文件名净化：去掉路径分隔符，限制长度 */
function sanitizeFileName(name: string): string {
  const base = name.replace(/[/\\]/g, "_").replace(/\.\.+/g, ".").trim();
  const safe = base.replace(/[<>:"|?* -]/g, "_");
  return safe.slice(0, 180) || `file-${Date.now()}`;
}

function sanitizeDir(name: string): string {
  const safe = sanitizeFileName(name);
  return safe.slice(0, 80) || "misc";
}
