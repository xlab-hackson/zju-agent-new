/**
 * @zju-agent/core — 平台无关核心类型
 *
 * 不依赖 Node-only API，不依赖 React。
 * 仅依赖 zod 做 schema 校验。
 */

export * from "./api.js";
export * from "./errors.js";
export * from "./tools.js";
export * from "./agent.js";
export * from "./settings.js";
export * from "./auth.js";
export * from "./domain/courses.js";
export * from "./domain/classroom.js";
export * from "./domain/notices.js";
export * from "./domain/zdbk.js";
export * from "./domain/network.js";
export * from "./domain/schedule.js";
