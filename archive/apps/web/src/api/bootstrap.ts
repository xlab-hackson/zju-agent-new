/**
 * 本地后端连接与 token 管理。
 *
 * 安全要求：前端不保存 ZJU 密码、cookie、LLM API Key。
 * 只保存后端启动时分配的本地访问 token（来自 /api/bootstrap）。
 * 生产期 token 不经接口下发，需 Electron 注入或文件读取；
 * 开发期 /api/bootstrap 返回 token。
 */

import { create } from "zustand";
import type { ApiResponse } from "@zju-agent/core";

const TOKEN_KEY = "zju-agent-access-token";

type BootstrapData = {
  server: string;
  version: string;
  isDev: boolean;
  accessToken: string | null;
  endpoints: Record<string, string>;
};

function getStoredToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

function setStoredToken(token: string | null) {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  } catch {
    // ignore
  }
}

/** 清除本地保存的 token（登出/401 时使用） */
export function clearStoredToken() {
  setStoredToken(null);
}

type BootstrapState = {
  isReady: boolean;
  isConnected: boolean;
  isDev: boolean;
  error: string | null;
  token: string | null;
  bootstrap: () => Promise<void>;
};

export const useBootstrapStore = create<BootstrapState>((set) => ({
  isReady: false,
  isConnected: false,
  isDev: false,
  error: null,
  token: getStoredToken(),
  bootstrap: async () => {
    try {
      const res = await fetch("/api/bootstrap");
      const json = (await res.json()) as ApiResponse<BootstrapData>;
      if (!json.ok) {
        set({ isReady: true, isConnected: false, error: json.error.message });
        return;
      }
      const data = json.data;
      // 开发期使用接口下发的 token；生产期保留既有 token（由 Electron 注入）
      const token = data.accessToken ?? getStoredToken();
      setStoredToken(token);
      set({
        isReady: true,
        isConnected: true,
        isDev: data.isDev,
        token,
        error: null,
      });
    } catch (err) {
      set({
        isReady: true,
        isConnected: false,
        error:
          err instanceof Error
            ? err.message
            : "无法连接本地后端服务，请确认后端已启动。",
      });
    }
  },
}));

/** 获取带 token 的 fetch 包装 */
export function useApiFetch() {
  const token = useBootstrapStore((s) => s.token);
  return async (path: string, init?: RequestInit) => {
    const headers = new Headers(init?.headers);
    if (token) headers.set("Authorization", `Bearer ${token}`);
    if (!headers.has("Accept")) headers.set("Accept", "application/json");
    const res = await fetch(path, { ...init, headers });
    // token 失效（后端重启/轮换）时：清除旧 token，重新 bootstrap 后用新 token 重试一次
    if (
      res.status === 401 &&
      !didAutoRecover &&
      (!init?.body || typeof init.body === "string")
    ) {
      didAutoRecover = true;
      try {
        clearStoredToken();
        const store = useBootstrapStore.getState();
        await store.bootstrap();
        const newToken = useBootstrapStore.getState().token;
        if (newToken && newToken !== token) {
          const retryHeaders = new Headers(init?.headers);
          retryHeaders.set("Authorization", `Bearer ${newToken}`);
          if (!retryHeaders.has("Accept")) {
            retryHeaders.set("Accept", "application/json");
          }
          return fetch(path, { ...init, headers: retryHeaders });
        }
      } finally {
        didAutoRecover = false;
      }
    }
    return res;
  };
}

/** 防止 401 → bootstrap → 401 的死循环（每轮只自动恢复一次） */
let didAutoRecover = false;

/** 用于二进制资源（文件预览/下载）的 URL：token 无法放 header，改走 query */
export function useTokenUrl() {
  const token = useBootstrapStore((s) => s.token);
  return (path: string) => {
    const sep = path.includes("?") ? "&" : "?";
    return token ? `${path}${sep}token=${encodeURIComponent(token)}` : path;
  };
}

/** 导出 token 供需要 query 形式的场景使用 */
export function useToken() {
  return useBootstrapStore((s) => s.token);
}
