import { useEffect, useRef, useState, useMemo } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { Components } from "react-markdown";
import { useFloatingChatStore } from "../stores/useFloatingChat.js";
import { useAppSettings } from "../api/settings.js";
import {
  useConversations,
  useConversation,
  useSendMessage,
  useConfirmTool,
  useDeleteConversation,
  type AgentEvent,
  type ChatMessage,
} from "../api/agent.js";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import {
  faCheck,
  faXmark,
  faSpinner,
  faPlus,
  faMinus,
  faExpand,
  faCompress,
  faTrashCan,
  faChevronDown,
  faGripVertical,
} from "@fortawesome/free-solid-svg-icons";
import { KoboyoIcon, type IconName } from "./ui/KoboyoIcon.js";

type PendingConfirmation = {
  confirmationId: string;
  toolName: string;
  summary: string;
  inputPreview: unknown;
};

type ToolStep = {
  id: string;
  name: string;
  input: unknown;
  status: "running" | "executing" | "done" | "failed";
  result?: unknown;
};

type LiveState = {
  assistantText: string;
  toolSteps: ToolStep[];
  thinking: boolean;
};

function initialLive(): LiveState {
  return { assistantText: "", toolSteps: [], thinking: false };
}

const QUICK_PROMPTS: { label: string; prompt: string; icon: IconName }[] = [
  { label: "今天有什么课？", prompt: "今天有什么课？请列出上课时间和地点。", icon: "calendar-days" },
  { label: "最近有什么作业要交？", prompt: "最近有什么作业要交？请按截止时间排序。", icon: "checklist-paper" },
  { label: "查一下这学期的考试安排", prompt: "查一下这学期的考试安排和考场地点。", icon: "exam-paper" },
  { label: "总结本学期的所有课程", prompt: "总结一下我本学期的所有课程和学分情况。", icon: "book-open" },
];

export function FloatingChat() {
  const {
    isOpen,
    isMinimized,
    isExpanded,
    activeConversationId,
    position,
    closeChat,
    toggleChat,
    minimizeChat,
    restoreChat,
    toggleExpand,
    setPosition,
    setActiveConversationId,
  } = useFloatingChatStore();

  const { data: conversations } = useConversations();
  const delConv = useDeleteConversation();

  // 默认自动选择第一个会话
  useEffect(() => {
    if (!activeConversationId && conversations && conversations.length > 0) {
      setActiveConversationId(conversations[0]!.id);
    }
  }, [activeConversationId, conversations, setActiveConversationId]);

  const [showConvDropdown, setShowConvDropdown] = useState(false);

  // 窗口尺寸
  const windowWidth = isExpanded ? 680 : 420;
  const windowHeight = isExpanded ? 700 : 560;

  // 窗口初始位置计算（默认右下角浮动）
  useEffect(() => {
    if (position === null && typeof window !== "undefined") {
      const x = Math.max(16, window.innerWidth - windowWidth - 24);
      const y = Math.max(16, window.innerHeight - windowHeight - 24);
      setPosition({ x, y });
    }
  }, [position, windowWidth, windowHeight, setPosition]);

  // 拖拽逻辑
  const dragRef = useRef<{
    startX: number;
    startY: number;
    initX: number;
    initY: number;
  } | null>(null);

  const [isDragging, setIsDragging] = useState(false);

  const handlePointerDown = (e: React.PointerEvent) => {
    // 忽略按钮、输入框、下拉框等交互元素的拖拽
    if ((e.target as HTMLElement).closest("button, input, select, textarea, a")) {
      return;
    }
    const currentX = position?.x ?? Math.max(16, window.innerWidth - windowWidth - 24);
    const currentY = position?.y ?? Math.max(16, window.innerHeight - windowHeight - 24);

    dragRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      initX: currentX,
      initY: currentY,
    };
    setIsDragging(true);

    const handlePointerMove = (moveEvt: PointerEvent) => {
      if (!dragRef.current) return;
      const deltaX = moveEvt.clientX - dragRef.current.startX;
      const deltaY = moveEvt.clientY - dragRef.current.startY;
      const maxX = Math.max(0, window.innerWidth - windowWidth);
      const maxY = Math.max(0, window.innerHeight - windowHeight);

      const nextX = Math.min(maxX, Math.max(0, dragRef.current.initX + deltaX));
      const nextY = Math.min(maxY, Math.max(0, dragRef.current.initY + deltaY));
      setPosition({ x: nextX, y: nextY });
    };

    const handlePointerUp = () => {
      dragRef.current = null;
      setIsDragging(false);
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
    };

    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp);
  };

  const activeConv = useMemo(
    () => (conversations ?? []).find((c) => c.id === activeConversationId),
    [conversations, activeConversationId],
  );

  return (
    <>
      {/* 浮动入口按钮：朱红「问学」印章（未打开或最小化时显示） */}
      {(!isOpen || isMinimized) && (
        <button
          onClick={isOpen && isMinimized ? restoreChat : toggleChat}
          className="group fixed bottom-20 right-4 z-40 flex size-16 -rotate-3 items-center justify-center rounded-[7px] bg-seal font-brush text-lg leading-tight tracking-[2px] text-paper-card shadow-[3px_4px_0_rgba(14,28,56,.3),0_14px_30px_-10px_rgba(176,58,46,.55)] ring-2 ring-paper-card/50 ring-offset-2 ring-offset-seal transition-all duration-200 hover:rotate-2 hover:scale-105 active:scale-95 lg:bottom-6 lg:right-6"
          title="打开 AI 校园助手 (⌘K)"
        >
          <span className="text-center">
            问学
            <span className="mt-0.5 block font-sans text-[9px] font-bold tracking-[1px] opacity-80">
              ⌘K
            </span>
          </span>
        </button>
      )}

      {/* 浮动对话窗口：纸墨信笺 */}
      {isOpen && !isMinimized && (
        <div
          className={`fixed z-50 flex flex-col overflow-hidden rounded-paper border-2 border-double border-gold/50 bg-paper-card shadow-2xl transition-shadow ${
            isDragging ? "select-none opacity-95" : ""
          }`}
          style={{
            left: position
              ? Math.min(Math.max(12, position.x), Math.max(12, (typeof window !== "undefined" ? window.innerWidth : 1000) - windowWidth - 12))
              : Math.max(12, (typeof window !== "undefined" ? window.innerWidth : 1000) - windowWidth - 24),
            top: position
              ? Math.min(Math.max(12, position.y), Math.max(12, (typeof window !== "undefined" ? window.innerHeight : 800) - windowHeight - 12))
              : Math.max(12, (typeof window !== "undefined" ? window.innerHeight : 800) - windowHeight - 24),
            width: windowWidth,
            height: windowHeight,
            maxWidth: "calc(100vw - 24px)",
            maxHeight: "calc(100vh - 84px)",
          }}
        >
          {/* 窗口头部：深墨蓝书脊条，拖拽手柄 + 会话切换 + 最小化/最大化/关闭按钮 */}
          <div
            onPointerDown={handlePointerDown}
            className="flex cursor-grab select-none items-center justify-between border-b border-gold-bright/30 bg-gradient-to-r from-qiushi-dark to-qiushi-deeper px-3.5 py-2.5 active:cursor-grabbing"
          >
            {/* 左侧：拖拽指示器与标题 */}
            <div className="flex min-w-0 items-center gap-2">
              <FontAwesomeIcon icon={faGripVertical} className="text-xs text-paper-deep/40" title="拖拽移动浮窗" />
              <KoboyoIcon name="inkbrush-calligraphy-pen" className="h-4 w-auto shrink-0 text-gold-bright" />
              <div className="relative">
                <button
                  onClick={() => setShowConvDropdown((v) => !v)}
                  className="flex max-w-[180px] items-center gap-1.5 truncate font-serif text-sm font-bold tracking-wide text-paper transition hover:text-gold-bright"
                >
                  <span className="truncate">{activeConv?.title || "新对话"}</span>
                  <FontAwesomeIcon icon={faChevronDown} className="text-[9px] text-paper-deep/50" />
                </button>

                {/* 会话下拉切换菜单 */}
                {showConvDropdown && (
                  <div className="absolute left-0 top-full z-50 mt-1.5 w-56 rounded-paper border border-ink/20 bg-paper-card p-1.5 shadow-paper-hover">
                    <button
                      onClick={() => {
                        setActiveConversationId(null);
                        setShowConvDropdown(false);
                      }}
                      className="mb-1 flex w-full items-center gap-1.5 rounded-paper bg-qiushi/10 px-2.5 py-1.5 text-xs font-bold tracking-wide text-qiushi transition hover:bg-qiushi/20"
                    >
                      <FontAwesomeIcon icon={faPlus} className="text-xs" />
                      <span>开启新对话</span>
                    </button>
                    <div className="max-h-48 space-y-0.5 overflow-y-auto">
                      {(conversations ?? []).map((c) => (
                        <div
                          key={c.id}
                          className={`group flex items-center justify-between rounded-paper px-2 py-1.5 text-xs ${
                            activeConversationId === c.id
                              ? "bg-paper-deep font-bold text-ink-deep"
                              : "text-ink-soft hover:bg-paper-deep/60"
                          }`}
                        >
                          <button
                            onClick={() => {
                              setActiveConversationId(c.id);
                              setShowConvDropdown(false);
                            }}
                            className="flex-1 truncate text-left"
                            title={c.title}
                          >
                            {c.title}
                          </button>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              delConv.mutate(c.id);
                              if (activeConversationId === c.id) setActiveConversationId(null);
                            }}
                            className="hidden px-1 text-ink-faint hover:text-seal group-hover:block"
                            title="删除会话"
                          >
                            <FontAwesomeIcon icon={faTrashCan} className="text-[11px]" />
                          </button>
                        </div>
                      ))}
                      {(conversations ?? []).length === 0 && (
                        <div className="py-2 text-center text-xs tracking-wide text-ink-faint">暂无历史会话</div>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* 右侧：操作按钮组 */}
            <div className="flex items-center gap-1">
              <button
                onClick={() => {
                  setActiveConversationId(null);
                  setShowConvDropdown(false);
                }}
                className="flex size-7 items-center justify-center rounded-paper text-paper-deep/60 transition hover:bg-gold-bright/15 hover:text-paper"
                title="开启新对话"
              >
                <FontAwesomeIcon icon={faPlus} className="text-xs" />
              </button>
              <button
                onClick={toggleExpand}
                className="flex size-7 items-center justify-center rounded-paper text-xs text-paper-deep/60 transition hover:bg-gold-bright/15 hover:text-paper"
                title={isExpanded ? "收起窗口" : "展开窗口"}
              >
                <FontAwesomeIcon icon={isExpanded ? faCompress : faExpand} className="text-xs" />
              </button>
              <button
                onClick={minimizeChat}
                className="flex size-7 items-center justify-center rounded-paper text-xs text-paper-deep/60 transition hover:bg-gold-bright/15 hover:text-paper"
                title="最小化"
              >
                <FontAwesomeIcon icon={faMinus} className="text-xs" />
              </button>
              <button
                onClick={closeChat}
                className="flex size-7 items-center justify-center rounded-paper text-xs text-paper-deep/60 transition hover:bg-seal/30 hover:text-paper"
                title="关闭浮窗"
              >
                <FontAwesomeIcon icon={faXmark} className="text-xs" />
              </button>
            </div>
          </div>

          {/* 窗口内容主体 */}
          <div className="flex min-h-0 flex-1 flex-col bg-paper/60">
            {activeConversationId ? (
              <ActiveConversationContent
                conversationId={activeConversationId}
              />
            ) : (
              <NewConversationContent
                onCreated={(id) => setActiveConversationId(id)}
              />
            )}
          </div>
        </div>
      )}
    </>
  );
}

/** 既有会话对话内容区 */
function ActiveConversationContent({
  conversationId,
}: {
  conversationId: string;
}) {
  const { prefillPrompt, setPrefillPrompt } = useFloatingChatStore();
  const [draft, setDraft] = useState("");
  const conv = useConversation(conversationId);
  // 稳定引用：?? [] 每次渲染新建数组会让下方 useEffect 依赖失稳
  const history = useMemo(() => conv.data?.messages ?? [], [conv.data]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [live, setLive] = useState<LiveState>(initialLive());
  const [pending, setPending] = useState<PendingConfirmation | null>(null);
  const [error, setError] = useState<string | null>(null);
  const send = useSendMessage();
  const confirm = useConfirmTool();

  useEffect(() => {
    if (prefillPrompt) {
      setDraft(prefillPrompt);
      setPrefillPrompt(null);
    }
  }, [prefillPrompt, setPrefillPrompt]);

  // 滚动到底部
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [history, live]);

  function handleEvent(e: AgentEvent) {
    switch (e.type) {
      case "confirmation_required":
        setPending({
          confirmationId: e.confirmationId,
          toolName: e.toolName,
          summary: e.summary,
          inputPreview: e.inputPreview,
        });
        break;
      case "error":
        setError(e.message);
        break;
      case "done":
        break;
      default:
        break;
    }
    setLive((prev) => {
      const next = { ...prev, toolSteps: [...prev.toolSteps] };
      switch (e.type) {
        case "text":
          next.assistantText = prev.assistantText + e.delta;
          next.thinking = false;
          break;
        case "tool_call_start":
          if (!prev.toolSteps.some((s) => s.id === e.toolCall.id)) {
            next.toolSteps = [
              ...prev.toolSteps,
              { id: e.toolCall.id, name: e.toolCall.name, input: e.toolCall.input, status: "running" },
            ];
          }
          break;
        case "tool_call_end": {
          const idx = prev.toolSteps.findIndex((s) => s.id === e.toolCall.id);
          if (idx === -1) {
            next.toolSteps = [
              ...prev.toolSteps,
              { id: e.toolCall.id, name: e.toolCall.name, input: e.toolCall.input, status: "executing" },
            ];
          } else {
            next.toolSteps = prev.toolSteps.map((s) =>
              s.id === e.toolCall.id
                ? { ...s, name: s.name || e.toolCall.name, input: s.input, status: s.status === "running" ? "executing" : s.status }
                : s,
            );
          }
          break;
        }
        case "tool_result":
          next.toolSteps = prev.toolSteps.map((s) =>
            s.id === e.toolCallId ? { ...s, status: e.ok ? "done" : "failed", result: e.result } : s,
          );
          break;
        case "done":
          return { ...prev, thinking: false };
      }
      return next;
    });
  }

  async function onSend(text: string) {
    if (!text.trim() || send.isPending) return;
    setError(null);
    setLive({ assistantText: "", toolSteps: [], thinking: true });
    try {
      await send.mutateAsync({
        conversationId,
        message: text,
        onEvent: handleEvent,
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "发送失败");
    }
  }

  async function onConfirm(decision: "approve" | "reject") {
    if (!pending || confirm.isPending) return;
    setLive((p) => ({ ...p, thinking: true }));
    try {
      await confirm.mutateAsync({
        confirmationId: pending.confirmationId,
        decision,
        onEvent: handleEvent,
      });
      setPending(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "确认失败");
    }
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      {/* 消息滚动区 */}
      <div ref={scrollRef} className="flex-1 space-y-3 overflow-y-auto p-4">
        {history.map((m) => (
          <HistoryBubble key={m.id} message={m} />
        ))}
        <LiveBubble state={live} />
        {error && (
          <div className="rounded-paper border border-seal/40 bg-seal/10 px-3 py-2 text-xs text-seal">
            {error}
          </div>
        )}
      </div>

      {/* 底部确认栏或输入区 */}
      {pending ? (
        <ConfirmBar pending={pending} onConfirm={onConfirm} pending2={confirm.isPending} />
      ) : (
        <Composer
          value={draft}
          onChange={setDraft}
          onSend={(text) => {
            setDraft("");
            void onSend(text);
          }}
          disabled={send.isPending}
        />
      )}
    </div>
  );
}

/** 新建会话内容区（含预设快捷引导） */
function NewConversationContent({
  onCreated,
}: {
  onCreated: (id: string) => void;
}) {
  const { prefillPrompt, setPrefillPrompt } = useFloatingChatStore();
  const [draft, setDraft] = useState("");
  const [live, setLive] = useState<LiveState>(initialLive());
  const [pending, setPending] = useState<PendingConfirmation | null>(null);
  const [error, setError] = useState<string | null>(null);
  const send = useSendMessage();
  const confirm = useConfirmTool();

  useEffect(() => {
    if (prefillPrompt) {
      setDraft(prefillPrompt);
      setPrefillPrompt(null);
    }
  }, [prefillPrompt, setPrefillPrompt]);

  function handleEvent(e: AgentEvent) {
    switch (e.type) {
      case "confirmation_required":
        setPending({
          confirmationId: e.confirmationId,
          toolName: e.toolName,
          summary: e.summary,
          inputPreview: e.inputPreview,
        });
        break;
      case "error":
        setError(e.message);
        break;
      case "done":
        if (e.conversationId) {
          onCreated(e.conversationId);
        }
        break;
      default:
        break;
    }
    setLive((prev) => {
      const next = { ...prev, toolSteps: [...prev.toolSteps] };
      switch (e.type) {
        case "text":
          next.assistantText = prev.assistantText + e.delta;
          next.thinking = false;
          break;
        case "tool_call_start":
          if (!prev.toolSteps.some((s) => s.id === e.toolCall.id)) {
            next.toolSteps = [
              ...prev.toolSteps,
              { id: e.toolCall.id, name: e.toolCall.name, input: e.toolCall.input, status: "running" },
            ];
          }
          break;
        case "tool_call_end": {
          const idx = prev.toolSteps.findIndex((s) => s.id === e.toolCall.id);
          if (idx === -1) {
            next.toolSteps = [
              ...prev.toolSteps,
              { id: e.toolCall.id, name: e.toolCall.name, input: e.toolCall.input, status: "executing" },
            ];
          } else {
            next.toolSteps = prev.toolSteps.map((s) =>
              s.id === e.toolCall.id
                ? { ...s, name: s.name || e.toolCall.name, input: s.input, status: s.status === "running" ? "executing" : s.status }
                : s,
            );
          }
          break;
        }
        case "tool_result":
          next.toolSteps = prev.toolSteps.map((s) =>
            s.id === e.toolCallId ? { ...s, status: e.ok ? "done" : "failed", result: e.result } : s,
          );
          break;
        case "done":
          return { ...prev, thinking: false };
      }
      return next;
    });
  }

  async function onSend(text: string) {
    if (!text.trim() || send.isPending) return;
    setError(null);
    setDraft("");
    setLive({ assistantText: "", toolSteps: [], thinking: true });
    try {
      await send.mutateAsync({ message: text, onEvent: handleEvent });
    } catch (err) {
      setError(err instanceof Error ? err.message : "发送失败");
    }
  }

  async function onConfirm(decision: "approve" | "reject") {
    if (!pending || confirm.isPending) return;
    setLive((p) => ({ ...p, thinking: true }));
    try {
      await confirm.mutateAsync({
        confirmationId: pending.confirmationId,
        decision,
        onEvent: handleEvent,
      });
      setPending(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "确认失败");
    }
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="flex flex-1 flex-col items-center justify-center overflow-y-auto p-4 text-center">
        {/* 印章式 AI 徽记 */}
        <div className="mb-2 flex size-14 -rotate-3 items-center justify-center rounded-[6px] border-2 border-qiushi bg-qiushi/5 font-brush text-xl text-qiushi shadow-seal">
          求索
        </div>
        <h3 className="font-serif text-sm font-black tracking-[2px] text-ink-deep">浙大校园智能助手</h3>
        <p className="mt-1 max-w-xs text-xs leading-relaxed text-ink-faint">
          我是你的专属 AI 助教，可以随时为你查询课表、作业、考场或下载课件。
        </p>

        {/* 快捷提问：书签条 */}
        <div className="w-full space-y-1.5 pt-4">
          {QUICK_PROMPTS.map((item) => (
            <button
              key={item.label}
              onClick={() => onSend(item.prompt)}
              disabled={send.isPending}
              className="group flex w-full items-center gap-2.5 rounded-paper border border-ink/15 bg-paper-card px-3 py-2 text-left text-xs tracking-wide text-ink transition hover:border-qiushi hover:bg-qiushi/5 hover:text-qiushi disabled:opacity-50"
            >
              <KoboyoIcon
                name={item.icon}
                className="h-4 w-auto shrink-0 text-ink-faint transition group-hover:text-gold"
              />
              <span>{item.label}</span>
            </button>
          ))}
        </div>

        <div className="w-full pt-2">
          <LiveBubble state={live} />
          {error && (
            <div className="w-full rounded-paper border border-seal/40 bg-seal/10 px-3 py-2 text-xs text-seal">
              {error}
            </div>
          )}
        </div>
      </div>

      {pending ? (
        <ConfirmBar pending={pending} onConfirm={onConfirm} pending2={confirm.isPending} />
      ) : (
        <Composer value={draft} onChange={setDraft} onSend={onSend} disabled={send.isPending} />
      )}
    </div>
  );
}

function LiveBubble({ state }: { state: LiveState }) {
  if (!state.thinking && !state.assistantText && state.toolSteps.length === 0) return null;
  return (
    <div className="mb-3 w-full text-left">
      {state.thinking && !state.assistantText && (
        <div className="mb-2 flex items-center gap-1.5 text-xs tracking-widest text-ink-faint">
          <span className="size-1.5 animate-pulse rounded-full bg-qiushi" />
          <span>思考中…</span>
        </div>
      )}
      {state.toolSteps.length > 0 && (
        <div className="mb-2 space-y-1">
          {state.toolSteps.map((s) => (
            <ToolStepView key={s.id} step={s} />
          ))}
        </div>
      )}
      {state.assistantText && <Bubble role="assistant">{state.assistantText}</Bubble>}
    </div>
  );
}

function ToolStepView({ step }: { step: ToolStep }) {
  const icon =
    step.status === "done" ? (
      <FontAwesomeIcon icon={faCheck} className="text-xs text-bamboo" />
    ) : step.status === "failed" ? (
      <FontAwesomeIcon icon={faXmark} className="text-xs text-seal" />
    ) : (
      <FontAwesomeIcon icon={faSpinner} className="animate-spin text-xs text-ink-faint" />
    );
  const label = toolLabel(step.name);
  return (
    <div className="rounded-paper border border-ink/15 bg-paper-card px-2.5 py-1.5 text-xs shadow-seal">
      <div className="flex items-center gap-1.5">
        <span>{icon}</span>
        <span className="font-bold tracking-wide text-ink">{label}</span>
      </div>
      {step.result != null && (
        <div className="mt-1 max-h-20 overflow-auto rounded-paper bg-paper-deep/60 p-1 font-mono text-[10px] text-ink-soft">
          {summarizeResult(step.result)}
        </div>
      )}
    </div>
  );
}

function toolLabel(name: string): string {
  const map: Record<string, string> = {
    zju_get_courses: "查询课程",
    zju_get_assignments: "查询作业",
    zju_get_course_materials: "查询课件",
    zju_get_quizzes: "查询小测",
    zju_get_exams: "查询考试",
    zju_get_timetable: "查询课表",
    zju_get_upcoming_schedule: "查询日程流",
    zju_download_course_material: "下载课件",
  };
  return map[name] ?? name;
}

function HistoryBubble({ message }: { message: ChatMessage }) {
  const { data: appSettings } = useAppSettings();
  const avatar =
    typeof appSettings?.avatarDataUrl === "string" ? appSettings.avatarDataUrl : undefined;
  if (message.role === "tool" || message.role === "system") return null;
  if (message.role === "assistant" && message.metadata?.toolCalls && !message.content) {
    const calls = message.metadata.toolCalls;
    return (
      <div className="mb-2 space-y-1">
        {calls.map((c) => (
          <div key={c.id} className="flex items-center gap-1.5 rounded-paper border border-ink/10 bg-paper-deep/60 px-2.5 py-1 text-xs text-ink-soft">
            <FontAwesomeIcon icon={faCheck} className="text-[11px] text-bamboo" />
            <span>{toolLabel(c.name)}</span>
          </div>
        ))}
      </div>
    );
  }
  return (
    <Bubble role={message.role === "user" ? "user" : "assistant"} avatar={avatar}>
      {message.content}
    </Bubble>
  );
}

function Bubble({
  role,
  children,
  avatar,
}: {
  role: "user" | "assistant";
  children: React.ReactNode;
  avatar?: string;
}) {
  const isUser = role === "user";
  const content = typeof children === "string" ? children : "";
  return (
    <div className={`mb-2.5 flex items-end gap-1.5 ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[88%] px-3.5 py-2 text-xs leading-relaxed shadow-seal ${
          isUser
            ? "rounded-paper rounded-br-sm bg-qiushi text-paper-card"
            : "rounded-paper rounded-bl-sm border border-ink/15 bg-paper-card text-ink"
        }`}
      >
        {isUser ? children : <ReactMarkdown remarkPlugins={[remarkGfm]} components={markdownComponents}>{content}</ReactMarkdown>}
      </div>
      {isUser && avatar && (
        <img
          src={avatar}
          alt=""
          className="mb-0.5 size-6 shrink-0 rounded-full object-cover ring-1 ring-gold-faint"
        />
      )}
    </div>
  );
}

const markdownComponents: Components = {
  ul({ children }) {
    return <div className="my-1.5 space-y-1">{children}</div>;
  },
  ol({ children }) {
    return <div className="my-1.5 space-y-1">{children}</div>;
  },
  li({ children }) {
    return (
      <div className="rounded-paper border border-ink/10 bg-paper-deep/50 px-2.5 py-1 text-xs">
        {children}
      </div>
    );
  },
  code({ children }) {
    const text = String(children ?? "");
    return text.includes("\n") ? (
      <pre className="my-1.5 overflow-auto rounded-paper bg-qiushi-deeper p-2 font-mono text-[11px] text-paper-deep">
        <code>{text}</code>
      </pre>
    ) : (
      <code className="rounded-paper bg-paper-deep px-1 py-0.5 font-mono text-[11px] text-ink">
        {text}
      </code>
    );
  },
};

function Composer({
  onSend,
  disabled,
  value,
  onChange,
}: {
  onSend: (text: string) => void;
  disabled: boolean;
  value?: string;
  onChange?: (v: string) => void;
}) {
  const [internal, setInternal] = useState("");
  const text = value ?? internal;
  const setText = (v: string) => {
    setInternal(v);
    onChange?.(v);
  };
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSend(text);
        if (!onChange) setInternal("");
      }}
      className="border-t border-ink/15 bg-paper-card p-2.5"
    >
      <div className="flex items-center gap-1.5">
        <input
          className="flex-1 rounded-paper border border-ink/20 bg-paper px-3 py-2 text-xs text-ink transition placeholder:text-ink-faint focus:border-qiushi focus:bg-paper-card focus:outline-none"
          placeholder="问问 AI 助手（如：明天有什么课）…"
          value={text}
          onChange={(e) => setText(e.target.value)}
          disabled={disabled}
        />
        <button
          type="submit"
          disabled={disabled || !text.trim()}
          className="rounded-paper bg-qiushi px-3.5 py-2 text-xs font-bold tracking-widest text-paper-card shadow-seal transition hover:bg-qiushi-dark disabled:opacity-40"
        >
          {disabled ? "…" : "发送"}
        </button>
      </div>
    </form>
  );
}

function ConfirmBar({
  pending,
  onConfirm,
  pending2,
}: {
  pending: PendingConfirmation;
  onConfirm: (d: "approve" | "reject") => void;
  pending2: boolean;
}) {
  return (
    <div className="border-t border-gold/50 bg-gold/10 p-2.5 text-xs">
      <div className="mb-1.5 flex items-center gap-1.5 font-bold tracking-wide text-gold">
        <KoboyoIcon name="stamp" className="h-3.5 w-auto" />
        <span>执行确认：</span>
        <span className="font-mono">{toolLabel(pending.toolName)}</span>
      </div>
      <div className="mb-2 truncate rounded-paper bg-paper-card/80 p-1.5 font-mono text-[10px] text-ink-soft">
        {pending.summary}
      </div>
      <div className="flex gap-1.5">
        <button
          onClick={() => onConfirm("approve")}
          disabled={pending2}
          className="flex-1 rounded-paper bg-bamboo py-1.5 text-xs font-bold tracking-wider text-paper-card transition hover:bg-[#256b29] disabled:opacity-50"
        >
          {pending2 ? "执行中…" : "同意"}
        </button>
        <button
          onClick={() => onConfirm("reject")}
          disabled={pending2}
          className="flex-1 rounded-paper border border-ink/20 bg-paper-card py-1.5 text-xs font-bold tracking-wider text-ink-soft transition hover:border-seal hover:text-seal disabled:opacity-50"
        >
          拒绝
        </button>
      </div>
    </div>
  );
}

function summarizeResult(result: unknown): string {
  try {
    const s = typeof result === "string" ? result : JSON.stringify(result, null, 2);
    return s.length > 300 ? s.slice(0, 300) + "…" : s;
  } catch {
    return String(result);
  }
}
