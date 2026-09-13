import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Layout } from "../components/Layout.js";
import { useApiFetch } from "../api/bootstrap.js";
import { useValidateCredential, useLogout } from "../api/auth.js";
import {
  fileToAvatarDataUrl,
  useAppSettings,
  useSaveAppSettings,
} from "../api/settings.js";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { faUser } from "@fortawesome/free-solid-svg-icons";
import { KoboyoIcon, type IconName } from "../components/ui/KoboyoIcon.js";
import { PageHead } from "../components/ui/Paper.js";

export function SettingsPage() {
  const apiFetch = useApiFetch();
  const navigate = useNavigate();
  const validate = useValidateCredential();
  const logout = useLogout();
  const [modelOpen, setModelOpen] = useState(false);

  useEffect(() => {
    if (window.location.hash === "#providers") {
      setModelOpen(true);
      setTimeout(() => {
        document.getElementById("providers")?.scrollIntoView({ behavior: "smooth" });
      }, 50);
    } else if (window.location.hash === "#zju") {
      setTimeout(() => {
        document.getElementById("zju")?.scrollIntoView({ behavior: "smooth" });
      }, 50);
    }
  }, []);
  const [model, setModel] = useState({
    id: crypto.randomUUID(),
    name: "默认模型",
    protocol: "openai" as "openai" | "anthropic",
    baseUrl: "https://api.openai.com/v1",
    apiKey: "",
    model: "gpt-4o-mini",
    enabled: true,
  });
  const [message, setMessage] = useState<string | null>(null);

  // 个性化：昵称 / 头像 / 默认提示词
  const { data: appSettings } = useAppSettings();
  const saveApp = useSaveAppSettings();
  const [nickname, setNickname] = useState("");
  const [persona, setPersona] = useState("");
  const [avatar, setAvatar] = useState<string | undefined>(undefined);
  const [profileLoaded, setProfileLoaded] = useState(false);

  useEffect(() => {
    if (profileLoaded || !appSettings) return;
    setNickname(typeof appSettings.nickname === "string" ? appSettings.nickname : "");
    setPersona(
      typeof appSettings.personaPrompt === "string" ? appSettings.personaPrompt : "",
    );
    setAvatar(
      typeof appSettings.avatarDataUrl === "string" ? appSettings.avatarDataUrl : undefined,
    );
    setProfileLoaded(true);
  }, [appSettings, profileLoaded]);

  async function onPickAvatar(file: File) {
    setMessage(null);
    try {
      setAvatar(await fileToAvatarDataUrl(file));
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "图片处理失败");
    }
  }

  async function saveProfile() {
    setMessage(null);
    try {
      // PUT /api/settings/app 是整体覆盖，必须带上已有字段
      await saveApp.mutateAsync({
        ...(appSettings ?? {}),
        nickname: nickname.trim(),
        personaPrompt: persona.trim(),
        avatarDataUrl: avatar,
      });
      setMessage("个性化设置已保存");
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "保存失败");
    }
  }

  function reload() {
    window.location.reload();
  }

  async function saveModel() {
    const res = await apiFetch("/api/settings/model-providers", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(model),
    });
    if (!res.ok) {
      setMessage("保存模型配置失败");
      return;
    }
    setModelOpen(false);
    setMessage("模型配置已保存");
    reload();
  }

  async function revalidate() {
    setMessage(null);
    try {
      const status = await validate.mutateAsync(undefined);
      setMessage(status.ok ? "ZJU 登录验证成功" : `验证失败：${status.message ?? ""}`);
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "验证失败");
    }
  }

  async function doLogout() {
    await logout.mutateAsync();
    setMessage("已登出，凭据已清除");
    reload();
  }

  return (
    <Layout>
      <div className="mx-auto max-w-2xl">
        <PageHead title="设置" sub="凭据、模型与个性化配置，全部仅存本机" />

        {message && (
          <div className="mb-5 rounded-paper border border-qiushi/40 bg-qiushi/10 px-4 py-2.5 text-sm tracking-wide text-qiushi">
            {message}
          </div>
        )}

        <div className="space-y-5">
          {/* 模型 Provider */}
          <Section id="providers" title="模型 Provider" icon="screen">
            <button
              onClick={() => setModelOpen((v) => !v)}
              className="btn-ink-primary !px-3.5 !py-1.5 text-sm"
            >
              {modelOpen ? "收起" : "新增 / 更新模型"}
            </button>
            {modelOpen && (
              <div className="mt-4 grid grid-cols-1 gap-3 md:grid-cols-2">
                <Field label="名称">
                  <input className="ink-input" value={model.name} onChange={(e) => setModel({ ...model, name: e.target.value })} />
                </Field>
                <Field label="协议">
                  <select className="ink-input" value={model.protocol} onChange={(e) => setModel({ ...model, protocol: e.target.value as "openai" | "anthropic" })}>
                    <option value="openai">OpenAI 兼容</option>
                    <option value="anthropic">Anthropic 兼容</option>
                  </select>
                </Field>
                <Field label="Base URL">
                  <input className="ink-input font-mono !text-xs" value={model.baseUrl} onChange={(e) => setModel({ ...model, baseUrl: e.target.value })} />
                </Field>
                <Field label="API Key">
                  <input autoComplete="off" className="ink-input font-mono !text-xs" type="password" value={model.apiKey} onChange={(e) => setModel({ ...model, apiKey: e.target.value })} />
                </Field>
                <Field label="模型">
                  <input className="ink-input font-mono !text-xs" value={model.model} onChange={(e) => setModel({ ...model, model: e.target.value })} />
                </Field>
                <div className="flex items-end">
                  <button onClick={saveModel} className="btn-ink-primary">
                    保存
                  </button>
                </div>
              </div>
            )}
            <p className="mt-3 text-xs leading-relaxed text-ink-faint">
              API Key 仅保存在本机加密存储，不会出现在任何接口响应中。
            </p>
          </Section>

          {/* ZJU 账号 */}
          <Section id="zju" title="ZJU 统一身份认证" icon="key">
            <div className="flex flex-wrap gap-2.5">
              <button onClick={revalidate} disabled={validate.isPending} className="btn-ink-primary !px-3.5 !py-1.5 text-sm disabled:opacity-50">
                {validate.isPending ? "验证中…" : "重新验证登录"}
              </button>
              <button onClick={() => navigate("/setup")} className="btn-ink-outline !px-3.5 !py-1.5 text-sm">
                修改账号
              </button>
              <button onClick={doLogout} disabled={logout.isPending} className="btn-ink-danger !px-3.5 !py-1.5 text-sm">
                {logout.isPending ? "登出中…" : "登出并清除凭据"}
              </button>
            </div>
            <p className="mt-3 text-xs leading-relaxed text-ink-faint">
              登出将清除本机保存的 ZJU 密码与所有校园服务 session。
            </p>
          </Section>

          {/* 个性化 */}
          <Section id="profile" title="个性化" icon="stamp">
            <div className="flex items-start gap-5">
              <div className="flex w-20 shrink-0 flex-col items-center gap-2.5">
                {avatar ? (
                  <img
                    src={avatar}
                    alt="头像"
                    className="size-16 rounded-full object-cover shadow-seal ring-2 ring-gold-faint"
                  />
                ) : (
                  <div className="flex size-16 items-center justify-center rounded-full border border-dashed border-ink/25 bg-paper-deep/60 text-ink-faint">
                    <FontAwesomeIcon icon={faUser} className="text-xl" />
                  </div>
                )}
                <label className="cursor-pointer rounded-paper border border-ink/25 px-2 py-1 text-xs tracking-wide text-ink-soft transition hover:border-gold hover:text-gold">
                  选择图片
                  <input
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={(e) => {
                      const file = e.target.files?.[0];
                      if (file) void onPickAvatar(file);
                      e.target.value = "";
                    }}
                  />
                </label>
                {avatar && (
                  <button
                    onClick={() => setAvatar(undefined)}
                    className="text-xs text-seal hover:underline"
                  >
                    移除头像
                  </button>
                )}
              </div>

              <div className="min-w-0 flex-1">
                <Field label="昵称（主页问候语，AI 也会这样称呼你）">
                  <input
                    className="ink-input"
                    maxLength={24}
                    value={nickname}
                    onChange={(e) => setNickname(e.target.value)}
                    placeholder="例如：小林"
                  />
                </Field>
                <Field label="默认提示词（注入所有 AI 对话，让回答更贴合你）">
                  <textarea
                    className="ink-input resize-y"
                    rows={4}
                    maxLength={1000}
                    value={persona}
                    onChange={(e) => setPersona(e.target.value)}
                    placeholder="例如：我是浙江大学计算机学院大二学生，爱好摄影和跑步，平时喜欢研究操作系统与分布式系统；回答时多结合课程与校园生活。"
                  />
                </Field>
                <div className="flex flex-wrap items-center gap-3">
                  <button
                    onClick={saveProfile}
                    disabled={saveApp.isPending}
                    className="btn-ink-primary"
                  >
                    {saveApp.isPending ? "保存中…" : "保存个性化设置"}
                  </button>
                  <span className="text-xs text-ink-faint">
                    头像压缩到 256px 后仅存本机，不会上传
                  </span>
                </div>
              </div>
            </div>
          </Section>

          {/* 权限策略 */}
          <Section title="权限策略" icon="stamp">
            <div className="rounded-paper border border-gold/45 bg-gold/10 p-3.5 text-xs leading-relaxed text-ink-soft">
              <p className="mb-1.5 font-bold tracking-wide text-gold">当前策略（默认）</p>
              <ul className="space-y-1">
                <li>· 查询类工具（课程/作业/考试）→ 直接执行</li>
                <li>· 下载单个资料 → 可直接执行</li>
                <li>· 批量下载 → 必须确认</li>
                <li>· 作业提交 → 必须确认</li>
                <li>· 校网充值 → 必须确认</li>
              </ul>
            </div>
            <p className="mt-3 text-xs leading-relaxed text-ink-faint">
              高风险操作必须经过用户确认，防止 Agent 静默执行。
            </p>
          </Section>

          {/* 清除数据 */}
          <Section title="数据管理" icon="folder">
            <div className="flex flex-wrap gap-2.5">
              <button className="btn-ink-danger !px-3.5 !py-1.5 text-sm">
                清除本地缓存
              </button>
              <button className="btn-ink-danger !px-3.5 !py-1.5 text-sm">
                清除会话历史
              </button>
              <button onClick={doLogout} className="btn-ink-danger !px-3.5 !py-1.5 text-sm">
                清除所有凭据
              </button>
            </div>
          </Section>

          {/* 导出日志 */}
          <Section title="导出日志" icon="scroll">
            <button className="btn-ink-outline !px-3.5 !py-1.5 text-sm">
              导出审计日志
            </button>
            <p className="mt-3 text-xs leading-relaxed text-ink-faint">
              导出本地操作记录，不包含密码和 API Key。
            </p>
          </Section>
        </div>
      </div>
    </Layout>
  );
}

/** 分区卡：卷签式标题 + 手绘图标 */
function Section({ id, title, icon, children }: { id?: string; title: string; icon?: IconName; children: React.ReactNode }) {
  return (
    <div id={id} className="paper-card scroll-mt-6 p-5">
      <h2 className="mb-4 flex items-center gap-2.5 border-b border-ink/10 pb-3 font-serif text-base font-black tracking-[2px] text-ink-deep">
        {icon && <KoboyoIcon name={icon} className="h-[18px] w-auto text-gold" />}
        {title}
      </h2>
      {children}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="mb-3 block">
      <span className="mb-1.5 block text-xs font-bold tracking-wide text-ink-soft">{label}</span>
      {children}
    </label>
  );
}
