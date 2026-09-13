/**
 * @zju-agent/storage — 存储抽象层（平台无关接口）。
 *
 * 桌面端：SQLite + OS Keychain + 文件系统。
 * 移动端：Capacitor Preferences + 原生插件。
 * 接口由各平台注入，业务层不直接依赖具体实现。
 *
 * 具体的 better-sqlite3 / 加密文件实现目前在 server 包内（平台相关）。
 */

export interface PlatformStorage {
  getSettings<T>(key: string): Promise<T | null>;
  setSettings<T>(key: string, value: T): Promise<void>;
  getCache<T>(key: string): Promise<T | null>;
  setCache<T>(key: string, value: T, ttlMs?: number): Promise<void>;
  clearCache(): Promise<void>;
}

/** 平台能力桥（见 ZJU_CAMPUS_AGENT_PROJECT.md 第 14 节） */
export interface PlatformBridge {
  openFolder(path: string): Promise<void>;
  showNotification(input: { title: string; body: string }): Promise<void>;
  selectFile(): Promise<string | null>;
}
