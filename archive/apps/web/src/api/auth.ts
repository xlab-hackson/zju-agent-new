/**
 * 前端认证 hook：登录验证、状态查询、登出。
 * 所有调用经本机 API，前端不保存密码。
 */

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { ApiResponse, AuthStatus } from "@zju-agent/core";
import { useApiFetch, clearStoredToken } from "./bootstrap.js";

export function useAuthStatus() {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["auth", "status"],
    queryFn: async () => {
      const res = await apiFetch("/api/auth/status");
      const json = (await res.json()) as ApiResponse<AuthStatus>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
  });
}

export function useValidateCredential() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (input?: Partial<{ username: string; password: string }>) => {
      const res = await apiFetch("/api/auth/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(input ?? {}),
      });
      const json = (await res.json()) as ApiResponse<AuthStatus>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["auth", "status"] });
      void qc.invalidateQueries({ queryKey: ["settings"] });
    },
  });
}

export function useLogout() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async () => {
      const res = await apiFetch("/api/auth/logout", { method: "POST" });
      const json = (await res.json()) as ApiResponse<{ ok: boolean }>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    onSuccess: () => {
      // 服务端已轮换本地访问 token：清除旧 token 并重载页面重新 bootstrap
      clearStoredToken();
      void qc.invalidateQueries({ queryKey: ["auth", "status"] });
      void qc.invalidateQueries({ queryKey: ["settings"] });
      window.location.reload();
    },
  });
}
