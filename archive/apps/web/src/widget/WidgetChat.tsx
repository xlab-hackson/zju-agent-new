/**
 * 桌面挂件里的 AI 对话条。
 *
 * 一次性问答：每次提问都是独立的一轮——服务端 `mode: "widget"` 不建会话、不落库，
 * 只挂只读工具，并在系统提示里强制简短回答。答案只留在挂件内，问下一个问题就覆盖。
 */
import { useEffect, useRef, useState } from "react";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import {
  faCircleNotch,
  faPaperPlane,
  faXmark,
} from "@fortawesome/free-solid-svg-icons";
import { useQuickAsk, type AgentEvent } from "../api/agent.js";

type Step = {
  id: string;
  name: string;
  status: "running" | "done" | "failed";
};

type QA = {
  question: string;
  answer: string;
  steps: Step[];
  status: "running" | "done" | "error";
  error?: string;
};

const TOOL_LABEL: Record<string, string> = {
  zju_get_courses: "查询课程",
  zju_get_assignments: "查询作业",
  zju_get_course_materials: "查询课件",
  zju_get_quizzes: "查询小测",
  zju_get_exams: "查询考试",
  zju_get_timetable: "查询课表",
  zju_get_daily_schedule: "查询当日日程",
  zju_get_upcoming_schedule: "查询日程流",
  zju_get_grades: "查询成绩",
  zju_get_notices: "查询通知公告",
};

function toolLabel(name: string): string {
  return TOOL_LABEL[name] ?? name;
}

export function WidgetChat() {
  const [draft, setDraft] = useState("");
  const [qa, setQa] = useState<QA | null>(null);
  const ask = useQuickAsk();
  const answerRef = useRef<HTMLDivElement>(null);
  const busy = ask.isPending;

  // 答案流式增长时保持滚动到底部
  useEffect(() => {
    const el = answerRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [qa]);

  function handleEvent(event: AgentEvent) {
    setQa((prev) => {
      if (!prev) return prev;
      switch (event.type) {
        case "text":
          return { ...prev, answer: prev.answer + event.delta };
        case "tool_call_end":
          return {
            ...prev,
            steps: [
              ...prev.steps,
              { id: event.toolCall.id, name: event.toolCall.name, status: "running" },
            ],
          };
        case "tool_result":
          return {
            ...prev,
            steps: prev.steps.map((step) =>
              step.id === event.toolCallId
                ? { ...step, status: event.ok ? "done" : "failed" }
                : step,
            ),
          };
        case "error":
          return { ...prev, status: "error", error: event.message };
        case "done":
          return prev.status === "error" ? prev : { ...prev, status: "done" };
        default:
          return prev;
      }
    });
  }

  async function submit() {
    const text = draft.trim();
    if (!text || busy) return;
    setDraft("");
    setQa({ question: text, answer: "", steps: [], status: "running" });
    try {
      await ask.mutateAsync({ message: text, onEvent: handleEvent });
    } catch (err) {
      setQa((prev) =>
        prev
          ? {
              ...prev,
              status: "error",
              error: err instanceof Error ? err.message : "发送失败",
            }
          : prev,
      );
    }
  }

  return (
    <div className="border-t border-white/10 px-2.5 py-2">
      {qa && (
        <div className="mb-2 rounded-lg bg-white/10 px-2.5 py-2 ring-1 ring-white/10">
          <div className="flex items-start justify-between gap-2">
            <span className="line-clamp-2 text-[10px] text-white/45">{qa.question}</span>
            <button
              type="button"
              onClick={() => setQa(null)}
              title="清空回答"
              className="shrink-0 rounded p-0.5 text-white/35 transition hover:bg-white/10 hover:text-white"
            >
              <FontAwesomeIcon icon={faXmark} className="text-[10px]" />
            </button>
          </div>

          {qa.steps.length > 0 && (
            <div className="mt-1.5 flex flex-wrap gap-1">
              {qa.steps.map((step) => (
                <span
                  key={step.id}
                  className="inline-flex items-center gap-1 rounded bg-white/10 px-1.5 py-0.5 text-[9px] text-white/55"
                >
                  {step.status === "running" ? (
                    <FontAwesomeIcon icon={faCircleNotch} className="animate-spin" />
                  ) : (
                    <span
                      className={`h-1 w-1 rounded-full ${
                        step.status === "done" ? "bg-emerald-400" : "bg-rose-400"
                      }`}
                    />
                  )}
                  {toolLabel(step.name)}
                </span>
              ))}
            </div>
          )}

          <div
            ref={answerRef}
            className="mt-1.5 max-h-40 overflow-y-auto whitespace-pre-wrap break-words text-[11px] leading-relaxed text-white/90"
          >
            {qa.answer}
            {qa.status === "running" && !qa.answer && (
              <span className="inline-flex items-center gap-1.5 text-white/45">
                <FontAwesomeIcon icon={faCircleNotch} className="animate-spin text-[9px]" />
                思考中…
              </span>
            )}
          </div>

          {qa.error && (
            <div className="mt-1 break-words text-[10px] leading-relaxed text-rose-200">
              {qa.error}
            </div>
          )}
        </div>
      )}

      <form
        onSubmit={(event) => {
          event.preventDefault();
          void submit();
        }}
        className="flex items-center gap-1.5"
      >
        <input
          value={draft}
          onChange={(event) => setDraft(event.target.value)}
          disabled={busy}
          maxLength={200}
          placeholder="问一句（只读 · 简短回答）"
          className="min-w-0 flex-1 rounded-lg bg-white/10 px-2.5 py-1.5 text-[11px] text-white placeholder:text-white/35 focus:bg-white/15 focus:outline-none focus:ring-1 focus:ring-white/25 disabled:opacity-50"
        />
        <button
          type="submit"
          disabled={busy || !draft.trim()}
          title="发送"
          className="shrink-0 rounded-lg bg-white/15 px-2.5 py-1.5 text-white/80 transition hover:bg-white/25 hover:text-white disabled:opacity-35"
        >
          <FontAwesomeIcon
            icon={busy ? faCircleNotch : faPaperPlane}
            className={`text-[11px] ${busy ? "animate-spin" : ""}`}
          />
        </button>
      </form>
    </div>
  );
}
