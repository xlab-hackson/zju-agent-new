/**
 * 智云课堂 (classroom.zju.edu.cn) 服务适配器。
 * 登录态由 login-zju 的 CLASSROOM 维护。
 * 接口路径需自行探测（fiz 未完整实现），此处提供框架与已知入口。
 */

import type { CLASSROOM } from "login-zju";
import type { ClassroomResource } from "@zju-agent/core";
import { AppError, ErrorCode } from "@zju-agent/core";

const BASE = "https://classroom.zju.edu.cn";

export class ClassroomService {
  constructor(private classroom: CLASSROOM) {}

  /** 资源列表。接口路径随页面变化，解析逻辑隔离在此。 */
  async getResources(): Promise<ClassroomResource[]> {
    // TODO: 探测实际接口。此处返回空列表，避免在未确认接口前误调用。
    // 实现时把解析逻辑隔离在 parseClassroomList(json) 内。
    void this.classroom;
    void BASE;
    return [];
  }

  async fetchResource(url: string): Promise<{
    stream: ReadableStream<Uint8Array>;
    contentType: string;
  }> {
    const res = await this.classroom.fetch(url);
    if (!res.ok) {
      throw new AppError(
        ErrorCode.FILE_DOWNLOAD_FAILED,
        `下载智云课堂资源失败，HTTP ${res.status}`,
      );
    }
    return {
      stream: res.body ?? new ReadableStream(),
      contentType: res.headers.get("content-type") ?? "application/octet-stream",
    };
  }
}
