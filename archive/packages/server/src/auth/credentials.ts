/**
 * 凭据安全存储。
 *
 * 优先级（见 ZJU_CAMPUS_AGENT_PROJECT.md 第 7.2 节）：
 * 1. OS Keychain（Windows: Credential Manager, macOS: Keychain, Linux: Secret Service）
 * 2. 本地加密文件（AES-256-GCM，key 由机器信息派生）
 * 3. 明文文件禁止作为默认方案
 *
 * 第一阶段实现「本地加密文件」方案，并预留 keychain 适配接口。
 * 加密 key 由 username + hostname + appDir 派生，配合 OS 文件权限 0o600。
 *
 * 文件格式：
 *   materialHash(64 hex) + JSON body
 * body 有两个版本，读取时自动识别，写入统一为 v2：
 *   v1（旧）: { [key]: { salt, iv, tag, ciphertext } }   每条独立 salt
 *   v2（新）: { version: 2, salt, entries: { [key]: { iv, tag, ciphertext } } }
 * v2 使用文件级共享 salt + 内存密钥缓存，避免每条凭据、每次写入都跑
 * 200k 轮 PBKDF2；GCM 的安全性由每条记录独立随机 IV 保证。
 */

import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
  pbkdf2Sync,
  createHash,
} from "node:crypto";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { hostname, userInfo } from "node:os";

const ALGO = "aes-256-gcm";
const PBKDF2_ITERATIONS = 200_000;
const KEY_LEN = 32;

type EncryptedEntry = {
  iv: string;
  tag: string;
  ciphertext: string;
};

/** v1 旧格式：每条凭据独立 salt（仅用于读取兼容，下次写入迁移为 v2） */
type StoredBlob = EncryptedEntry & {
  salt: string;
};

type StoredFileV2 = {
  version: 2;
  salt: string;
  entries: Record<string, EncryptedEntry>;
};

/** 平台无关的凭据存储接口，未来 Electron/Capacitor 可注入原生实现 */
export interface CredentialStore {
  get<T>(key: string): Promise<T | null>;
  set<T>(key: string, value: T): Promise<void>;
  delete(key: string): Promise<void>;
  clear(): Promise<void>;
}

/** 派生加密 key 的密料。机器相关，但不写入配置文件。 */
function deriveMaterial(appDir: string): string {
  const user = (() => {
    try {
      return userInfo().username;
    } catch {
      return "unknown-user";
    }
  })();
  return `${user}@${hostname()}:${appDir}:zju-campus-agent:v1`;
}

function deriveKey(material: string, salt: Buffer): Buffer {
  return pbkdf2Sync(material, salt, PBKDF2_ITERATIONS, KEY_LEN, "sha256");
}

function isV2File(parsed: unknown): parsed is StoredFileV2 {
  return (
    typeof parsed === "object" &&
    parsed !== null &&
    "version" in parsed &&
    (parsed as { version?: unknown }).version === 2 &&
    "salt" in parsed &&
    "entries" in parsed
  );
}

/** 本地加密文件凭据存储 */
export class EncryptedFileCredentialStore implements CredentialStore {
  private readonly credFile: string;
  /** v2 文件级 salt（base64）。复用它使密钥缓存持续命中 */
  private currentSalt: string | null = null;
  private keyCache: { material: string; salt: string; key: Buffer } | null = null;

  constructor(appDir: string) {
    this.credFile = join(appDir, "credentials.enc");
    if (!existsSync(appDir)) {
      mkdirSync(appDir, { recursive: true });
    }
  }

  async get<T>(key: string): Promise<T | null> {
    const map = this.readAll();
    const raw = map[key];
    if (!raw) return null;
    return JSON.parse(raw) as T;
  }

  async set<T>(key: string, value: T): Promise<void> {
    const map = this.readAll();
    map[key] = JSON.stringify(value);
    this.writeAll(map);
  }

  async delete(key: string): Promise<void> {
    const map = this.readAll();
    delete map[key];
    this.writeAll(map);
  }

  async clear(): Promise<void> {
    this.writeAll({});
  }

  private readAll(): Record<string, string> {
    if (!existsSync(this.credFile)) return {};
    try {
      const raw = readFileSync(this.credFile);
      // 文件格式: materialHash(64 hex) + json body
      const material = deriveMaterial(this.credFile);
      const expectedHash = createHash("sha256")
        .update(material)
        .digest()
        .toString("hex");
      const fileHash = raw.subarray(0, 64).toString("utf8");
      if (fileHash !== expectedHash) {
        // 机器环境变化，无法解密，返回空（提示用户重新输入凭据）
        console.warn(
          "[credentials] 机器环境变化（用户名/主机名/目录变更），凭据库无法解密，视为空。请重新保存凭据。",
        );
        this.currentSalt = null;
        this.keyCache = null;
        return {};
      }
      const parsed: unknown = JSON.parse(raw.subarray(64).toString("utf8"));
      const out: Record<string, string> = {};

      if (isV2File(parsed)) {
        this.currentSalt = parsed.salt;
        const key = this.getKey(material, Buffer.from(parsed.salt, "base64"));
        for (const [k, entry] of Object.entries(parsed.entries)) {
          const decrypted = this.decryptEntry(entry, key);
          if (decrypted !== null) out[k] = decrypted;
        }
      } else {
        // v1 旧格式：每条独立 salt。读出的内容下次写入时自动迁移为 v2。
        this.currentSalt = null;
        const blobs = parsed as Record<string, StoredBlob>;
        for (const [k, blob] of Object.entries(blobs)) {
          const decrypted = this.decryptBlob(blob, material);
          if (decrypted !== null) out[k] = decrypted;
        }
      }
      return out;
    } catch (err) {
      console.warn(
        `[credentials] 凭据库读取失败：${err instanceof Error ? err.message : String(err)}`,
      );
      return {};
    }
  }

  private writeAll(map: Record<string, string>): void {
    const material = deriveMaterial(this.credFile);
    const materialHash = createHash("sha256")
      .update(material)
      .digest()
      .toString("hex");
    const salt =
      this.currentSalt !== null
        ? Buffer.from(this.currentSalt, "base64")
        : randomBytes(16);
    const key = this.getKey(material, salt);

    const entries: Record<string, EncryptedEntry> = {};
    for (const [k, v] of Object.entries(map)) {
      entries[k] = this.encryptEntry(v, key);
    }
    const file: StoredFileV2 = {
      version: 2,
      salt: salt.toString("base64"),
      entries,
    };
    const body = Buffer.from(JSON.stringify(file), "utf8");
    const out = Buffer.concat([Buffer.from(materialHash, "utf8"), body]);
    writeFileSync(this.credFile, out, { mode: 0o600 });
    this.currentSalt = file.salt;
  }

  /** PBKDF2 结果缓存：material+salt 不变时跳过重复派生 */
  private getKey(material: string, salt: Buffer): Buffer {
    const saltB64 = salt.toString("base64");
    if (
      this.keyCache &&
      this.keyCache.material === material &&
      this.keyCache.salt === saltB64
    ) {
      return this.keyCache.key;
    }
    const key = deriveKey(material, salt);
    this.keyCache = { material, salt: saltB64, key };
    return key;
  }

  private encryptEntry(plain: string, key: Buffer): EncryptedEntry {
    const iv = randomBytes(12);
    const cipher = createCipheriv(ALGO, key, iv);
    const ciphertext = Buffer.concat([
      cipher.update(plain, "utf8"),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();
    return {
      iv: iv.toString("base64"),
      tag: tag.toString("base64"),
      ciphertext: ciphertext.toString("base64"),
    };
  }

  private decryptEntry(entry: EncryptedEntry, key: Buffer): string | null {
    try {
      const iv = Buffer.from(entry.iv, "base64");
      const tag = Buffer.from(entry.tag, "base64");
      const ciphertext = Buffer.from(entry.ciphertext, "base64");
      const decipher = createDecipheriv(ALGO, key, iv);
      decipher.setAuthTag(tag);
      const plain = Buffer.concat([
        decipher.update(ciphertext),
        decipher.final(),
      ]);
      return plain.toString("utf8");
    } catch {
      console.warn("[credentials] 单条凭据解密失败（密文损坏或被篡改），已跳过。");
      return null;
    }
  }

  /** v1 旧格式解密（每条独立 salt） */
  private decryptBlob(blob: StoredBlob, material: string): string | null {
    try {
      const salt = Buffer.from(blob.salt, "base64");
      const key = this.getKey(material, salt);
      return this.decryptEntry(
        { iv: blob.iv, tag: blob.tag, ciphertext: blob.ciphertext },
        key,
      );
    } catch {
      console.warn("[credentials] 单条凭据解密失败（密文损坏或被篡改），已跳过。");
      return null;
    }
  }
}

/** 待存储的敏感凭据类型 */
export type StoredCredentials = {
  zju?: { username: string; password: string };
  modelProviders?: Array<{
    id: string;
    name: string;
    protocol: "openai" | "anthropic";
    baseUrl: string;
    apiKey: string;
    model: string;
    enabled: boolean;
  }>;
};
