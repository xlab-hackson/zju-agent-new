import { z } from "zod";

/** login-zju 支持的服务 key，与 ZJU_CAMPUS_AGENT_PROJECT.md 第 7.1 节一致 */
export type ServiceKey =
  | "zjuam"
  | "courses"
  | "classroom"
  | "zdbk"
  | "form"
  | "yqfkgl"
  | "open"
  | "cc98"
  | "eta"
  | "apiLib"
  | "bookingLib"
  | "alt";

export const serviceKeySchema = z.enum([
  "zjuam",
  "courses",
  "classroom",
  "zdbk",
  "form",
  "yqfkgl",
  "open",
  "cc98",
  "eta",
  "apiLib",
  "bookingLib",
  "alt",
]);

export type ZjuCredential = {
  username: string;
  password: string;
};

export type AuthStatus = {
  ok: boolean;
  username?: string;
  message?: string;
  services?: Partial<Record<ServiceKey, boolean>>;
};

/** 前端可获得的脱敏凭据状态 */
export type CredentialStatus = {
  hasZjuCredential: boolean;
  zjuUsernameMasked?: string;
  hasModelApiKey: boolean;
  modelProviderName?: string;
};

export function maskUsername(username: string): string {
  return username ?? "";
}
