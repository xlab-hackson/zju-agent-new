/**
 * 个性化设置（昵称 / 头像 / 默认提示词）读写。
 *
 * 服务端 `GET /api/settings` 返回的 appSettings 是一个 JSON blob（存在 SQLite
 * settings 表的 "app-settings" 键下）；`PUT /api/settings/app` 是**整体覆盖**，
 * 所以保存时必须把已有字段一起带上。
 */

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import type { ApiResponse } from "@zju-agent/core";
import { useApiFetch } from "./bootstrap.js";

export type AppSettingsData = {
  nickname?: string;
  avatarDataUrl?: string;
  personaPrompt?: string;
  [key: string]: unknown;
};

export function useAppSettings() {
  const apiFetch = useApiFetch();
  return useQuery({
    queryKey: ["settings", "app"],
    queryFn: async () => {
      const res = await apiFetch("/api/settings");
      const json = (await res.json()) as ApiResponse<{
        appSettings?: AppSettingsData;
      }>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data.appSettings ?? {};
    },
    retry: false,
    throwOnError: false,
  });
}

export function useSaveAppSettings() {
  const apiFetch = useApiFetch();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async (settings: AppSettingsData) => {
      const res = await apiFetch("/api/settings/app", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(settings),
      });
      const json = (await res.json()) as ApiResponse<{ ok: boolean }>;
      if (!json.ok) throw new Error(json.error.message);
      return json.data;
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ["settings", "app"] });
    },
  });
}

/**
 * 把用户选的图片压成 256×256 的 JPEG data URL（居中裁剪，约 20–40KB）。
 * 头像存进本地 SQLite 的 settings 表，不外传。
 */
export async function fileToAvatarDataUrl(file: File): Promise<string> {
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error("读取图片失败"));
    reader.readAsDataURL(file);
  });

  const img = await new Promise<HTMLImageElement>((resolve, reject) => {
    const el = new Image();
    el.onload = () => resolve(el);
    el.onerror = () => reject(new Error("图片解码失败，请换一张图片"));
    el.src = dataUrl;
  });

  const SIZE = 256;
  const canvas = document.createElement("canvas");
  canvas.width = SIZE;
  canvas.height = SIZE;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("当前浏览器不支持图片处理");
  const scale = Math.max(SIZE / img.width, SIZE / img.height);
  const w = img.width * scale;
  const h = img.height * scale;
  ctx.drawImage(img, (SIZE - w) / 2, (SIZE - h) / 2, w, h);
  return canvas.toDataURL("image/jpeg", 0.85);
}
