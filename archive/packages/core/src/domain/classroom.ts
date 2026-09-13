/** 智云课堂 (classroom.zju.edu.cn) 领域类型 */

export type ClassroomResourceType =
  | "courseware"
  | "transcript"
  | "video"
  | "unknown";

export type ClassroomResource = {
  id: string;
  courseName?: string;
  title: string;
  type: ClassroomResourceType;
  downloadUrl?: string;
  createdAt?: string;
  metadata?: Record<string, unknown>;
};
