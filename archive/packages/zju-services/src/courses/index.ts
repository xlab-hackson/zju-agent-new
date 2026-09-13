/**
 * 学在浙大 (courses.zju.edu.cn) 服务适配器。
 * 接口路径与字段解析参考自 fiz 的 Rust 实现（见仓库 fiz/src-tauri/src/courseware.rs 等）。
 * 使用 login-zju 的 COURSES.fetch()，登录态自动维护。
 */

import type { COURSES } from "login-zju";
import {
  AppError,
  ErrorCode,
  type Semester,
  type Course,
  type CourseMaterial,
  type Assignment,
  type Quiz,
  type CourseFile,
} from "@zju-agent/core";

const BASE = "https://courses.zju.edu.cn";

export class CoursesService {
  constructor(private courses: COURSES) {}

  private reloginPromise: Promise<boolean> | null = null;

  private async relogin(): Promise<boolean> {
    if (this.reloginPromise) {
      return this.reloginPromise;
    }
    this.reloginPromise = (async () => {
      const orig = console.log;
      try {
        console.log = () => {};
        return await this.courses.login();
      } finally {
        console.log = orig;
        this.reloginPromise = null;
      }
    })();
    return this.reloginPromise;
  }

  private async fetchWithAutoRelogin(
    url: string,
    init?: RequestInit,
  ): Promise<Response> {
    const doFetch = () => this.courses.fetch(url, init);
    let res = await doFetch();

    if (res.status === 401 || res.status === 403 || res.status === 302) {
      try {
        await this.relogin();
        res = await doFetch();
      } catch (err) {
        console.warn(
          `[zju-services/courses] 会话过期自动重登录失败：${err instanceof Error ? err.message : String(err)}`,
        );
      }
    } else if (res.ok) {
      const contentType = res.headers.get("content-type") || "";
      if (contentType.includes("text/html")) {
        const clone = res.clone();
        const text = await clone.text();
        if (text.includes("zjuam.zju.edu.cn") || text.includes("统一身份认证")) {
          try {
            await this.relogin();
            res = await doFetch();
          } catch (err) {
            console.warn(
              `[zju-services/courses] 响应为登录页，自动重登录失败：${err instanceof Error ? err.message : String(err)}`,
            );
          }
        }
      }
    }
    return res;
  }

  /** 学期列表 */
  async getSemesters(): Promise<Semester[]> {
    const res = await this.fetchWithAutoRelogin(`${BASE}/api/my-semesters?`);
    const json = (await res.json()) as {
      semesters?: Array<{
        id: number;
        name: string;
        is_active: boolean;
      }>;
    };
    const raw = json.semesters ?? [];
    // 复用 fiz 的活跃学期判定逻辑：春夏拆 {春,夏}、秋冬拆 {秋,冬}
    const semesters: Semester[] = raw.map((s) => ({
      id: String(s.id),
      name: s.name,
      isActive: s.is_active,
    }));
    const active = raw.find(
      (s) => s.is_active && ["春夏", "秋冬", "短"].includes(s.name.slice(9)),
    );
    if (active) {
      const year = active.name.slice(0, 9);
      const term = active.name.slice(9);
      const more = term === "春夏" ? ["春", "夏"] : term === "秋冬" ? ["秋", "冬"] : [];
      for (const s of semesters) {
        if (s.name.startsWith(year) && more.includes(s.name.slice(9))) {
          s.isActive = true;
        }
      }
    }
    return semesters;
  }

  /** 课程列表 */
  async getCourses(): Promise<Course[]> {
    const url =
      `${BASE}/api/my-courses?conditions=` +
      encodeURIComponent(
        JSON.stringify({
          status: ["ongoing", "notStarted", "ended"],
          keyword: "",
          classify_type: "recently_started",
          display_studio_list: false,
        }),
      ) +
      `&fields=id,name,semester_id,course_attributes&page=1&page_size=1000`;
    const res = await this.fetchWithAutoRelogin(url);
    const json = (await res.json()) as {
      courses?: Array<{
        id: number;
        name: string;
        semester_id: number;
        course_attributes?: { teaching_class_name?: string | null };
      }>;
    };
    return (json.courses ?? []).map((c) => ({
      id: String(c.id),
      name: c.name,
      semesterId: String(c.semester_id),
      teachingClassName: c.course_attributes?.teaching_class_name ?? undefined,
      isActive: false,
    }));
  }

  /** 课程资料 */
  async getMaterials(courseId: string): Promise<CourseMaterial[]> {
    const url =
      `${BASE}/api/course/${encodeURIComponent(courseId)}/coursewares?conditions=` +
      encodeURIComponent(
        JSON.stringify({
          category: null,
          itemsSortBy: { predicate: "chapter", reverse: false },
          ignore_activity_types: ["lesson"],
        }),
      ) +
      `&page=1&page_size=1000`;
    const res = await this.fetchWithAutoRelogin(url);
    const json = (await res.json()) as {
      activities?: Array<{
        id: number;
        title: string;
        uploads?: Array<{
          id: number;
          reference_id: number;
          name: string;
        }>;
      }>;
    };
    return (json.activities ?? []).map((a) => ({
      id: String(a.id),
      courseId,
      title: a.title,
      files: (a.uploads ?? []).map((u) => ({
        id: String(u.id),
        referenceId: String(u.reference_id),
        name: u.name.trim(),
      })),
    }));
  }

  /** 作业列表 */
  async getAssignments(courseId: string, courseName: string): Promise<Assignment[]> {
    const url = `${BASE}/api/courses/${encodeURIComponent(courseId)}/homework-activities?page=1&page_size=1000`;
    const res = await this.fetchWithAutoRelogin(url);
    const json = (await res.json()) as {
      homework_activities?: Array<{
        id: number;
        title: string;
        deadline: string;
        submitted: boolean;
        is_closed: boolean;
        data?: { description?: string };
        uploads?: Array<{ id: number; reference_id: number; name: string }>;
      }>;
    };
    return (json.homework_activities ?? [])
      .map((h) => ({
        id: String(h.id),
        courseId,
        courseName,
        title: h.title,
        deadline: h.deadline,
        submitted: h.submitted,
        description: h.data?.description,
        attachments: (h.uploads ?? []).map((u) => ({
          id: String(u.id),
          referenceId: String(u.reference_id),
          name: u.name,
        })),
      }));
  }

  /** 测试/小测列表 */
  async getQuizzes(courseId: string, courseName: string): Promise<Quiz[]> {
    const url = `${BASE}/api/courses/${encodeURIComponent(courseId)}/exam-list?page=1&page_size=100`;
    const res = await this.fetchWithAutoRelogin(url);
    const json = (await res.json()) as {
      exams?: Array<{
        id: number;
        title: string;
        end_time: string;
        submission_count: number;
        is_closed: boolean;
      }>;
    };
    return (json.exams ?? [])
      .filter((e) => !e.is_closed)
      .map((e) => ({
        id: String(e.id),
        courseId,
        courseName,
        title: e.title,
        deadline: e.end_time,
        submitted: e.submission_count > 0,
        url: `${BASE}/course/${courseId}/learning-activity#/exam/${e.id}`,
      }));
  }

  /**
   * 获取文件下载流。
   * @param fileId 文件的 upload id（CourseFile.id），非 referenceId。
   *               用于 GET /api/uploads/{id}/blob 或 /api/uploads/document/{id}/url
   * @param opts.officePdf Office 文件取 PDF 预览版（走 /document/{id}/url）
   */
  async fetchFile(fileId: string, opts?: { officePdf?: boolean }): Promise<{
    stream: ReadableStream<Uint8Array>;
    contentType: string;
  }> {
    const url = opts?.officePdf
      ? `${BASE}/api/uploads/document/${encodeURIComponent(fileId)}/url?preview=true`
      : `${BASE}/api/uploads/${encodeURIComponent(fileId)}/blob`;
    const res = await this.fetchWithAutoRelogin(url);
    if (!res.ok) {
      // 明确指出 fileId 与状态，便于排查 id 误用（referenceId vs upload id）
      throw new AppError(
        ErrorCode.FILE_DOWNLOAD_FAILED,
        `下载文件失败，HTTP ${res.status}（fileId=${fileId}，请确认使用的是 upload id 而非 referenceId）`,
      );
    }
    if (opts?.officePdf) {
      const meta = (await res.json()) as { url?: string };
      if (!meta.url) {
        throw new AppError(ErrorCode.FILE_DOWNLOAD_FAILED, "预览 URL 缺失。");
      }
      const inner = await this.fetchWithAutoRelogin(meta.url);
      if (!inner.ok) {
        throw new AppError(
          ErrorCode.FILE_DOWNLOAD_FAILED,
          `下载预览文件失败，HTTP ${inner.status}`,
        );
      }
      return {
        stream: inner.body ?? new ReadableStream(),
        contentType: inner.headers.get("content-type") ?? "application/octet-stream",
      };
    }
    return {
      stream: res.body ?? new ReadableStream(),
      contentType: res.headers.get("content-type") ?? "application/octet-stream",
    };
  }
}

export type { CourseFile };
