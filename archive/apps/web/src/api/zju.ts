/**
 * 学在浙大相关接口 hooks。
 * 所有调用经本机 API，前端只接收脱敏数据与领域类型。
 */

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type {
  ApiResponse,
  Semester,
  Course,
  CourseMaterial,
  Assignment,
  Quiz,
  Exam,
  TimetableEntry,
  Grade,
  UpcomingSchedule48h,
  NoticeFetchResult,
} from "@zju-agent/core";
import { useApiFetch } from "./bootstrap.js";

export function useSemesters() {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "semesters"],
    queryFn: async () => {
      const res = await apiFetch("/api/zju/semesters");
      const json = (await res.json()) as ApiResponse<Semester[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 30 * 60_000,
    // 未登录/服务不可用时静默失败，由消费方用 data ?? [] 兜底
    retry: false,
    throwOnError: false,
  });
}

export function useCourses() {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "courses"],
    queryFn: async () => {
      const res = await apiFetch("/api/zju/courses");
      const json = (await res.json()) as ApiResponse<Course[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 30 * 60_000,
    retry: false,
    throwOnError: false,
  });
}

export function useMaterials(courseId: string | undefined) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "materials", courseId],
    enabled: !!courseId,
    queryFn: async () => {
      const res = await apiFetch(
        `/api/zju/courses/${courseId}/materials`,
      );
      const json = (await res.json()) as ApiResponse<CourseMaterial[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 30 * 60_000,
  });
}

export function useCourseAssignments(courseId: string | undefined) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "assignments", "course", courseId],
    enabled: !!courseId,
    queryFn: async () => {
      const res = await apiFetch(
        `/api/zju/courses/${courseId}/assignments`,
      );
      const json = (await res.json()) as ApiResponse<Assignment[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 10 * 60_000,
  });
}

export function useCourseQuizzes(courseId: string | undefined) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "quizzes", courseId],
    enabled: !!courseId,
    queryFn: async () => {
      const res = await apiFetch(
        `/api/zju/courses/${courseId}/quizzes`,
      );
      const json = (await res.json()) as ApiResponse<Quiz[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 10 * 60_000,
  });
}

/** 聚合所有课程待办作业 */
export function useAllAssignments() {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "assignments", "all"],
    queryFn: async () => {
      const res = await apiFetch("/api/zju/assignments");
      const json = (await res.json()) as ApiResponse<Assignment[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 10 * 60_000,
    retry: false,
    throwOnError: false,
  });
}

export type DownloadMaterialInput = {
  courseId: string;
  materialId: string;
  fileId: string;
  fileName: string;
  officePdf?: boolean;
};

export function useDownloadMaterial() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input: DownloadMaterialInput) => {
      const res = await apiFetch("/api/zju/materials/download", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(input),
      });
      const json = (await res.json()) as ApiResponse<{
        id: string;
        fileName: string;
        filePath: string;
        size: number;
      }>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["files", "downloads"] });
    },
  });
}

/** 下载记录 */
export type DownloadRecord = {
  id: string;
  source: "courses" | "classroom";
  fileName: string;
  filePath: string;
  status: "completed" | "failed";
  size: number;
  mimeType?: string;
  courseId?: string;
  materialId?: string;
  fileId?: string;
  createdAt: string;
};

export function useDownloads() {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["files", "downloads"],
    queryFn: async () => {
      const res = await apiFetch("/api/files/downloads");
      const json = (await res.json()) as ApiResponse<{
        downloadDir: string;
        records: DownloadRecord[];
      }>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
  });
}

export function useDeleteDownload() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ id, purge }: { id: string; purge?: boolean }) => {
      const qs = purge ? "?purge=1" : "";
      const res = await apiFetch(`/api/files/downloads/${id}${qs}`, {
        method: "DELETE",
      });
      const json = (await res.json()) as ApiResponse<{ id: string }>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["files", "downloads"] });
    },
  });
}

/** 预览/下载链接：inline=1 内联预览，否则 attachment 下载。
 *  token 通过 query 传递（二进制资源无法用 Authorization header）。 */
export function downloadPreviewUrl(
  id: string,
  token: string | null,
  inline = true,
): string {
  const params = new URLSearchParams();
  if (inline) params.set("inline", "1");
  if (token) params.set("token", token);
  const qs = params.toString();
  return `/api/files/downloads/${id}/preview${qs ? `?${qs}` : ""}`;
}

/** 考试安排 */
export function useExams(xnxq01id?: string) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "exams", xnxq01id ?? "default"],
    queryFn: async () => {
      const qs = xnxq01id ? `?xnxq01id=${encodeURIComponent(xnxq01id)}` : "";
      const res = await apiFetch(`/api/zju/exams${qs}`);
      const json = (await res.json()) as ApiResponse<Exam[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 60 * 60_000,
    retry: false,
    throwOnError: false,
  });
}

/** 课程表 */
export function useTimetable(xnxq01id?: string) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "timetable", xnxq01id ?? "default"],
    queryFn: async () => {
      const qs = xnxq01id ? `?xnxq01id=${encodeURIComponent(xnxq01id)}` : "";
      const res = await apiFetch(`/api/zju/timetable${qs}`);
      const json = (await res.json()) as ApiResponse<TimetableEntry[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 24 * 60 * 60_000,
    retry: false,
    throwOnError: false,
  });
}

/** 成绩 */
export function useGrades(xnxq01id?: string) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "grades", xnxq01id ?? "default"],
    queryFn: async () => {
      const qs = xnxq01id ? `?xnxq01id=${encodeURIComponent(xnxq01id)}` : "";
      const res = await apiFetch(`/api/zju/grades${qs}`);
      const json = (await res.json()) as ApiResponse<Grade[]>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 60 * 60_000,
    retry: false,
    throwOnError: false,
  });
}

/** 学校通知公告（素质拓展平台 + 教务系统公开源，免浙大凭据） */
export function useNotices(limit = 20, refreshSeq = 0) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "notices", limit, refreshSeq],
    queryFn: async () => {
      const refresh = refreshSeq > 0 ? "&refresh=1" : "";
      const res = await apiFetch(`/api/zju/notices?limit=${limit}${refresh}`);
      const json = (await res.json()) as ApiResponse<NoticeFetchResult>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 30 * 60_000,
    retry: false,
    throwOnError: false,
  });
}

/** 接下来 48 小时日程流与待办（仿 Celechron 页面） */
export function useUpcomingSchedule48h(xnxq01id?: string) {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["zju", "schedule", "upcoming-48h", xnxq01id ?? "default"],
    queryFn: async () => {
      const qs = xnxq01id ? `?xnxq01id=${encodeURIComponent(xnxq01id)}` : "";
      const res = await apiFetch(`/api/zju/schedule/upcoming-48h${qs}`);
      const json = (await res.json()) as ApiResponse<UpcomingSchedule48h>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    staleTime: 5 * 60_000,
    refetchInterval: 60_000,
    retry: false,
    throwOnError: false,
  });
}

