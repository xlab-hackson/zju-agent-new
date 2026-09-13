import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { mkdtempSync, rmSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EncryptedFileCredentialStore } from "../auth/credentials.js";

let dir: string;

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "zju-cred-test-"));
});

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe("EncryptedFileCredentialStore", () => {
  it("set/get 加密往返", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    await store.set("zju", { username: "3230100001", password: "s3cret-密码" });
    expect(await store.get("zju")).toEqual({
      username: "3230100001",
      password: "s3cret-密码",
    });
  });

  it("get 不存在的 key 返回 null", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    expect(await store.get("nope")).toBeNull();
  });

  it("delete 后 get 返回 null", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    await store.set("a", { v: 1 });
    await store.delete("a");
    expect(await store.get("a")).toBeNull();
  });

  it("clear 清空全部条目", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    await store.set("a", { v: 1 });
    await store.set("b", { v: 2 });
    await store.clear();
    expect(await store.get("a")).toBeNull();
    expect(await store.get("b")).toBeNull();
  });

  it("新实例（模拟进程重启）可读回已存凭据", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    await store.set("zju", { username: "u", password: "p" });
    const store2 = new EncryptedFileCredentialStore(dir);
    expect(await store2.get("zju")).toEqual({ username: "u", password: "p" });
  });

  it("密文文件不包含明文（凭据落盘加密）", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    await store.set("zju", { username: "plainuser", password: "plainpass" });
    const raw = readFileSync(join(dir, "credentials.enc")).toString("utf8");
    expect(raw).not.toContain("plainuser");
    expect(raw).not.toContain("plainpass");
  });

  it("写入为 v2 格式（文件级 salt）", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    await store.set("zju", { username: "u", password: "p" });
    const raw = readFileSync(join(dir, "credentials.enc"));
    const body = JSON.parse(raw.subarray(64).toString("utf8")) as {
      version?: number;
      salt?: string;
      entries?: Record<string, unknown>;
    };
    expect(body.version).toBe(2);
    expect(typeof body.salt).toBe("string");
    expect(body.entries).toHaveProperty("zju");
    expect((body.entries!.zju as { salt?: unknown }).salt).toBeUndefined();
  });

  it("文件不存在时读取返回空（不抛错）", async () => {
    const store = new EncryptedFileCredentialStore(join(dir, "not-exist-subdir"));
    expect(await store.get("any")).toBeNull();
  });

  it("多条凭据混合读写互不干扰", async () => {
    const store = new EncryptedFileCredentialStore(dir);
    await store.set("zju", { username: "u1", password: "p1" });
    await store.set("modelProviders", [
      { id: "x", name: "X", protocol: "openai", baseUrl: "https://x", apiKey: "sk-x", model: "gpt", enabled: true },
    ]);
    expect(await store.get("zju")).toEqual({ username: "u1", password: "p1" });
    expect(await store.get<{ id: string }[]>("modelProviders")).toEqual([
      { id: "x", name: "X", protocol: "openai", baseUrl: "https://x", apiKey: "sk-x", model: "gpt", enabled: true },
    ]);
  });
});
