/** 学在浙大 (courses.zju.edu.cn) 领域类型 */

export type Semester = {
  id: string;
  name: string;
  isActive: boolean;
};

export type Course = {
  id: string;
  name: string;
  semesterId: string;
  teachingClassName?: string;
  isActive: boolean;
};

export type CourseFile = {
  /** 文件的 upload id，用于下载接口 /api/uploads/{id}/blob */
  id: string;
  /** 内部引用 id，不可用于下载，仅用于去重/关联 */
  referenceId?: string;
  name: string;
  size?: number;
  mimeType?: string;
};

export type CourseMaterial = {
  id: string;
  courseId: string;
  courseName?: string;
  title: string;
  files: CourseFile[];
};

export type Assignment = {
  id: string;
  courseId: string;
  courseName: string;
  title: string;
  deadline?: string;
  submitted: boolean;
  description?: string;
  attachments: CourseFile[];
};

export type Quiz = {
  id: string;
  courseId: string;
  courseName: string;
  title: string;
  deadline?: string;
  submitted: boolean;
  url?: string;
};

export type SubmitAssignmentInput = {
  assignmentId: string;
  filePath: string;
  comment?: string;
};

export type DownloadMaterialInput = {
  courseId: string;
  materialId: string;
  fileId: string;
  fileName: string;
};

export type DownloadedFile = {
  id: string;
  source: "courses" | "classroom";
  fileName: string;
  filePath: string;
  size: number;
};
