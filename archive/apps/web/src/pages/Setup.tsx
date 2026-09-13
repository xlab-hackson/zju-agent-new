import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useApiFetch } from "../api/bootstrap.js";
import { useValidateCredential } from "../api/auth.js";
import type { ApiResponse, AuthStatus } from "@zju-agent/core";
import { KoboyoIcon } from "../components/ui/KoboyoIcon.js";
import { SealStamp } from "../components/ui/Paper.js";

const STEPS = [
  { key: "intro", title: "欢迎使用" },
  { key: "model", title: "配置大模型" },
  { key: "zju", title: "配置 ZJU 账号" },
  { key: "done", title: "完成" },
] as const;

export function SetupPage() {
  const apiFetch = useApiFetch();
  const navigate = useNavigate();
  const validate = useValidateCredential();
  const [step, setStep] = useState(0);
  const [authError, setAuthError] = useState<string | null>(null);

  // 模型 provider 表单
  const [model, setModel] = useState({
    id: crypto.randomUUID(),
    name: "默认模型",
    protocol: "openai" as "openai" | "anthropic",
    baseUrl: "https://api.openai.com/v1",
    apiKey: "",
    model: "gpt-4o-mini",
    enabled: true,
  });

  // ZJU 凭据表单
  const [zju, setZju] = useState({ username: "", password: "" });

  const next = () => setStep((s) => Math.min(s + 1, STEPS.length - 1));
  const prev = () => setStep((s) => Math.max(s - 1, 0));

  async function saveModel() {
    try {
      const res = await apiFetch("/api/settings/model-providers", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(model),
      });
      if (!res.ok) throw new Error("保存模型配置失败");
      setAuthError(null);
      next();
    } catch (e) {
      setAuthError(e instanceof Error ? e.message : "保存失败");
    }
  }

  async function saveZju() {
    setAuthError(null);
    try {
      const status = await validate.mutateAsync({
        username: zju.username,
        password: zju.password,
      });
      if (status.ok) {
        next();
      } else {
        setAuthError(status.message ?? "登录验证失败");
      }
    } catch (e) {
      setAuthError(e instanceof Error ? e.message : "登录验证失败");
    }
  }

  // 完成步可跳过 ZJU（若已验证则进 Dashboard）
  async function skipAndFinish() {
    const res = await apiFetch("/api/auth/status");
    const json = (await res.json()) as ApiResponse<AuthStatus>;
    if (json.ok && json.data.ok) {
      navigate("/");
    } else {
      // 未配置也允许进入，后续可在设置补
      navigate("/");
    }
  }

  return (
    <div className="mx-auto max-w-2xl p-6 sm:p-10">
      {/* 顶部栏：书院名 + 跳过向导按钮 */}
      <div className="mb-6 flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <SealStamp size="md" rotate={-3}>求是</SealStamp>
          <div>
            <div className="font-serif text-lg font-black tracking-[3px] text-ink-deep">
              求是书院
            </div>
            <div className="mt-0.5 text-xs tracking-wide text-ink-faint">初始化配置向导</div>
          </div>
        </div>
        <button
          onClick={() => navigate("/")}
          className="flex items-center gap-1 rounded-paper px-2.5 py-1.5 text-xs tracking-wide text-ink-soft transition hover:bg-paper-deep hover:text-gold"
          title="随时可在「设置」页面重新配置"
        >
          <span>跳过向导，直接进入</span>
          <span>&rarr;</span>
        </button>
      </div>

      {/* 步骤进度条 */}
      <div className="mb-6 flex items-center gap-2">
        {STEPS.map((s, i) => (
          <div
            key={s.key}
            className={`h-1.5 flex-1 rounded-full transition-colors ${
              i <= step ? "bg-qiushi" : "bg-ink/15"
            }`}
            title={s.title}
          />
        ))}
      </div>

      {authError && (
        <div className="mb-4 rounded-paper border border-seal/40 bg-seal/10 px-4 py-2.5 text-sm text-seal">
          {authError}
        </div>
      )}

      <div className="paper-card p-6 sm:p-8">
        {step === 0 && (
          <div>
            <div className="mb-4 flex items-center gap-2.5">
              <KoboyoIcon name="inkbrush-calligraphy-pen" className="h-6 w-auto text-gold" />
              <h2 className="font-serif text-xl font-black tracking-wide text-ink-deep">
                欢迎使用浙大校园智能助手
              </h2>
            </div>
            <p className="mb-4 text-sm leading-relaxed text-ink-soft">
              本应用采用本地优先架构，所有校园服务请求都经过本机后端，
              账号密码、API Key 仅保存在你的设备上，不上传任何远端服务器。
            </p>
            <p className="mb-6 text-sm leading-relaxed text-ink-faint">
              接下来可配置：大模型来源、ZJU 统一身份认证账号（均可随时跳过，后续在「设置」中配置）。
            </p>
            <div className="flex flex-wrap items-center gap-3">
              <button onClick={next} className="btn-ink-primary">
                开始配置
              </button>
              <button onClick={() => navigate("/")} className="btn-ink-outline">
                暂不配置，直接进入
              </button>
            </div>
          </div>
        )}

        {step === 1 && (
          <div>
            <div className="mb-5 flex items-center gap-2.5">
              <KoboyoIcon name="screen" className="h-6 w-auto text-gold" />
              <h2 className="font-serif text-xl font-black tracking-wide text-ink-deep">配置大模型</h2>
            </div>
            <div className="grid grid-cols-1 gap-3">
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
                <input autoComplete="off" className="ink-input font-mono !text-xs" type="password" value={model.apiKey} onChange={(e) => setModel({ ...model, apiKey: e.target.value })} placeholder="仅保存在本机，不上传" />
              </Field>
              <Field label="模型">
                <input className="ink-input font-mono !text-xs" value={model.model} onChange={(e) => setModel({ ...model, model: e.target.value })} />
              </Field>
            </div>
            <div className="mt-6 flex items-center justify-between">
              <button onClick={prev} className="rounded-paper px-4 py-2 text-sm text-ink-soft transition hover:bg-paper-deep">上一步</button>
              <div className="flex items-center gap-2">
                <button onClick={next} className="rounded-paper px-4 py-2 text-sm text-ink-faint transition hover:bg-paper-deep hover:text-ink-soft">
                  稍后配置
                </button>
                <button onClick={saveModel} disabled={validate.isPending} className="btn-ink-primary disabled:opacity-50">
                  保存并下一步
                </button>
              </div>
            </div>
          </div>
        )}

        {step === 2 && (
          <div>
            <div className="mb-3 flex items-center gap-2.5">
              <KoboyoIcon name="key" className="h-6 w-auto text-gold" />
              <h2 className="font-serif text-xl font-black tracking-wide text-ink-deep">配置 ZJU 账号</h2>
            </div>
            <p className="mb-4 text-sm leading-relaxed text-ink-faint">
              用于登录浙江大学统一身份认证。账号密码经本机加密存储，不上传任何远端服务器。
              点击「保存并验证」会通过 login-zju 真实访问 zjuam.zju.edu.cn 验证。
            </p>
            <div className="grid grid-cols-1 gap-3">
              <Field label="学号 / 工号">
                <input autoComplete="username" className="ink-input" value={zju.username} onChange={(e) => setZju({ ...zju, username: e.target.value })} />
              </Field>
              <Field label="密码">
                <input autoComplete="new-password" className="ink-input" type="password" value={zju.password} onChange={(e) => setZju({ ...zju, password: e.target.value })} />
              </Field>
            </div>
            <div className="mt-6 flex items-center justify-between">
              <button onClick={prev} className="rounded-paper px-4 py-2 text-sm text-ink-soft transition hover:bg-paper-deep">上一步</button>
              <div className="flex items-center gap-2">
                <button onClick={skipAndFinish} className="rounded-paper px-4 py-2 text-sm text-ink-faint transition hover:bg-paper-deep hover:text-ink-soft">稍后配置</button>
                <button onClick={saveZju} disabled={validate.isPending || !zju.username || !zju.password} className="btn-ink-primary disabled:opacity-50">
                  {validate.isPending ? "验证中…" : "保存并验证"}
                </button>
              </div>
            </div>
          </div>
        )}

        {step === 3 && (
          <div className="py-6 text-center">
            <div className="mb-4 flex justify-center">
              <SealStamp size="lg" rotate={4}>功成</SealStamp>
            </div>
            <h2 className="mb-3 font-serif text-xl font-black tracking-wide text-ink-deep">配置完成</h2>
            <p className="mb-6 text-sm text-ink-soft">现在可以开始使用校园智能助手了。</p>
            <button onClick={() => navigate("/")} className="btn-ink-primary !px-6 !py-2.5">
              开始使用助手
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-xs font-bold tracking-wide text-ink-soft">{label}</span>
      {children}
    </label>
  );
}
