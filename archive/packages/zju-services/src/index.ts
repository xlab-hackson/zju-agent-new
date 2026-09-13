/**
 * @zju-agent/zju-services — 校园服务适配层
 *
 * 封装 npm 包 login-zju，提供领域化方法，
 * 解析校园系统返回数据，屏蔽 cookie/重定向/登录细节，
 * 统一错误处理为 AppError。
 *
 * 服务实例懒加载，所有服务共享同一个 ZJUAM 实例。
 */

import type { ZJUAM, COURSES, ZDBK, CLASSROOM } from "login-zju";
import { AppError, ErrorCode } from "@zju-agent/core";
import { CoursesService } from "./courses/index.js";
import { ClassroomService } from "./classroom/index.js";
import { ZdbkService, semesterToXnxq01id, activeXnxq01ids, getAcademicPeriod, currentXnxq01id } from "./zdbk/index.js";
import { NetworkService } from "./network/index.js";
import { CalendarService } from "./calendar/index.js";
import { NoticeService } from "./notices/index.js";

export type ZjuServiceInstances = {
  am: ZJUAM;
  courses: COURSES;
  zdbk: ZDBK;
  classroom: CLASSROOM;
};

export type ZjuServiceAdapters = {
  courses: CoursesService;
  classroom: ClassroomService;
  zdbk: ZdbkService;
  network: NetworkService;
  calendar: CalendarService;
};

export interface ZjuServices {
  /** 用账号密码登录统一身份认证（不强制登录各子服务） */
  loginZjuam(username: string, password: string): Promise<boolean>;
  /** 获取已登录的服务实例集合（懒加载，凭据缺失时抛 AppError） */
  getInstances(username: string, password: string): Promise<ZjuServiceInstances>;
  /** 获取领域适配器（依赖已登录实例） */
  getAdapters(): Promise<ZjuServiceAdapters>;
  /** 重置：清除缓存的 ZJUAM 实例与登录态 */
  reset(): Promise<void>;
}

export function createZjuServices(): ZjuServices {
  return new ZjuServicesImpl();
}

/**
 * login-zju 无日志开关，会在 stdout 打印含 CAS ticket/oauth code 的
 * 重定向 URL（票据泄露面）。登录期间临时静音 console.log；
 * 用串行队列保证并发请求下不相互污染。
 */
let quietQueue: Promise<unknown> = Promise.resolve();

function runQuiet<T>(fn: () => Promise<T>): Promise<T> {
  const run = quietQueue.then(async () => {
    const orig = console.log;
    try {
      console.log = () => {};
      return await fn();
    } finally {
      console.log = orig;
    }
  });
  quietQueue = run.catch(() => undefined);
  return run;
}

class ZjuServicesImpl implements ZjuServices {
  private instances: ZjuServiceInstances | null = null;
  private adapters: ZjuServiceAdapters | null = null;

  async loginZjuam(username: string, password: string): Promise<boolean> {
    return runQuiet(async () => {
      const { ZJUAM } = await import("login-zju");
      const am = new ZJUAM(username, password);
      try {
        // login-zju 的 login() 返回重定向 URL 或抛错
        await am.login();
        this.instances = await this.buildInstances(am);
        this.adapters = {
          courses: new CoursesService(this.instances.courses),
          classroom: new ClassroomService(this.instances.classroom),
          zdbk: new ZdbkService(this.instances.zdbk),
          network: new NetworkService(),
          calendar: new CalendarService(),
        };
        return true;
      } catch (err) {
        const message =
          err && typeof err === "object" && "message" in err
            ? String((err as { message?: unknown }).message)
            : "统一身份认证失败。";
        throw new AppError(ErrorCode.ZJU_AUTH_FAILED, message, {
          retryable: true,
        });
      }
    });
  }

  async getInstances(
    username: string,
    password: string,
  ): Promise<ZjuServiceInstances> {
    if (this.instances) return this.instances;
    const ok = await this.loginZjuam(username, password);
    if (!ok || !this.instances) {
      throw new AppError(ErrorCode.ZJU_AUTH_FAILED, "统一身份认证失败。");
    }
    return this.instances;
  }

  async getAdapters(): Promise<ZjuServiceAdapters> {
    if (this.adapters) return this.adapters;
    throw new AppError(
      ErrorCode.ZJU_CREDENTIAL_MISSING,
      "尚未登录，无法获取校园服务适配器。",
      { retryable: false },
    );
  }

  async reset(): Promise<void> {
    this.instances = null;
    this.adapters = null;
  }

  private async buildInstances(am: ZJUAM): Promise<ZjuServiceInstances> {
    const { COURSES, ZDBK, CLASSROOM } = await import("login-zju");
    return {
      am,
      courses: new COURSES(am),
      zdbk: new ZDBK(am),
      classroom: new CLASSROOM(am),
    };
  }
}

export {
  CoursesService,
  ClassroomService,
  ZdbkService,
  NetworkService,
  CalendarService,
  NoticeService,
  semesterToXnxq01id,
  activeXnxq01ids,
  getAcademicPeriod,
  currentXnxq01id,
};
