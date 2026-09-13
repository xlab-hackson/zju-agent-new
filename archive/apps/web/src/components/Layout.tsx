import { type ReactNode, useState, useEffect } from "react";
import { NavLink } from "react-router-dom";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import {
  faXmark,
  faChartSimple,
} from "@fortawesome/free-solid-svg-icons";
import { KoboyoIcon, type IconName } from "./ui/KoboyoIcon.js";
import { FloatingChat } from "./FloatingChat.js";
import { useFloatingChatStore } from "../stores/useFloatingChat.js";

/** 学业导航（桌面侧栏 + 移动端底栏共用）；卷号取汉字数字，如线装书目录 */
const NAV_ITEMS: {
  to: string;
  label: string;
  /** 移动端底栏显示的短名（不传用 label） */
  shortLabel?: string;
  /** 侧栏卷号 */
  juan: string;
  icon: IconName;
  end?: boolean;
}[] = [
  { to: "/", label: "工作台", juan: "壹", icon: "notebook-desk", end: true },
  { to: "/courses", label: "课程表", juan: "贰", icon: "calendar-grid" },
  { to: "/assignments", label: "待办作业", shortLabel: "作业", juan: "叁", icon: "checklist-paper" },
  { to: "/exams", label: "考试安排", shortLabel: "考试", juan: "肆", icon: "exam-paper" },
  { to: "/school-info", label: "学校信息", shortLabel: "通知", juan: "伍", icon: "announcement-horn" },
];

const FOOT_ITEMS: { to: string; label: string; icon: IconName }[] = [
  { to: "/downloads", label: "下载", icon: "folder" },
  { to: "/settings", label: "设置", icon: "cartoon-settings" },
];

export function Layout({
  children,
  rightPanel,
}: {
  children: ReactNode;
  rightPanel?: ReactNode;
}) {
  const [mobileRightOpen, setMobileRightOpen] = useState(false);
  const { openChat } = useFloatingChatStore();

  // 全局 ⌘K / Ctrl+K 快捷唤起 AI 对话浮窗
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        openChat();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [openChat]);

  return (
    <div className="flex min-h-screen flex-col lg:flex-row">
      {/* === 桌面端侧栏：线装书书脊 === */}
      <aside className="relative hidden shrink-0 flex-col border-r-2 border-double border-gold/40 bg-gradient-to-b from-qiushi-dark to-qiushi-deeper p-5 text-paper-deep lg:sticky lg:top-0 lg:flex lg:h-screen lg:w-60">
        {/* 装订线（书脊左侧金色虚线） */}
        <div
          aria-hidden
          className="pointer-events-none absolute bottom-0 left-2.5 top-0 w-px bg-[repeating-linear-gradient(180deg,rgba(201,162,39,.45)_0_6px,transparent_6px_14px)]"
        />

        {/* 品牌：求是印章 + 书院名 */}
        <div className="mb-8 flex items-center gap-3 pl-2">
          <div className="flex size-11 shrink-0 -rotate-3 items-center justify-center rounded-[5px] bg-seal font-brush text-lg leading-none text-paper-card shadow-seal ring-2 ring-paper-card/50 ring-offset-2 ring-offset-seal">
            求是
          </div>
          <div>
            <div className="font-serif text-lg font-black tracking-[3px] text-paper">
              求是书院
            </div>
            <div className="mt-1 font-mono text-[9px] tracking-[2.5px] text-gold-bright">
              ZJU CAMPUS AGENT
            </div>
          </div>
        </div>

        <div className="mb-3 flex items-center gap-2 px-2 text-[11px] tracking-[4px] text-gold-bright/85">
          <span className="shrink-0">学业导航</span>
          <span className="h-px flex-1 bg-gradient-to-r from-gold-bright/50 to-transparent" />
        </div>

        <nav className="flex flex-1 flex-col gap-0.5 overflow-y-auto">
          {NAV_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) =>
                `group relative flex items-center gap-3 border-l-2 px-3.5 py-2.5 text-sm tracking-[2px] transition-all ${
                  isActive
                    ? "border-gold-bright bg-gradient-to-r from-qiushi/70 to-transparent font-bold text-paper"
                    : "border-transparent text-paper-deep/60 hover:bg-gold-bright/10 hover:text-paper"
                }`
              }
            >
              {({ isActive }) => (
                <>
                  <span
                    className={`font-mono text-[10px] ${
                      isActive ? "text-gold-bright" : "text-gold-bright/50"
                    }`}
                  >
                    {item.juan}
                  </span>
                  <KoboyoIcon
                    name={item.icon}
                    className={`h-[18px] w-auto transition-transform group-hover:-rotate-3 ${
                      isActive ? "text-paper" : "text-paper-deep/70"
                    }`}
                  />
                  <span>{item.label}</span>
                </>
              )}
            </NavLink>
          ))}
        </nav>

        {/* 校训落款 */}
        <div className="my-4 text-center font-brush text-base tracking-[6px] text-gold-bright/70">
          求是创新
        </div>

        {/* 底部：下载 + 设置 */}
        <div className="flex gap-2 border-t border-gold-bright/25 pt-3.5">
          {FOOT_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              className={({ isActive }) =>
                `flex flex-1 items-center justify-center gap-2 rounded-paper border px-2 py-2 text-xs tracking-[2px] transition-all ${
                  isActive
                    ? "border-gold-bright bg-gold-bright/15 font-bold text-paper"
                    : "border-gold-bright/30 text-paper-deep/60 hover:border-gold-bright/70 hover:bg-gold-bright/10 hover:text-paper"
                }`
              }
            >
              <KoboyoIcon name={item.icon} className="h-3.5 w-auto" />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </div>
      </aside>

      {/* === 中间主内容区 === */}
      <main className="flex-1 overflow-auto px-4 py-5 pb-24 lg:px-10 lg:py-8 lg:pb-8">
        {children}
      </main>

      {/* === 桌面端右侧辅助面板 === */}
      {rightPanel && (
        <aside className="hidden shrink-0 border-l border-ink/15 bg-paper-card/60 p-5 lg:sticky lg:top-0 lg:block lg:h-screen lg:overflow-y-auto lg:w-72 xl:w-80">
          {rightPanel}
        </aside>
      )}

      {/* === 移动端：右栏可折叠面板按钮 === */}
      {rightPanel && (
        <>
          <button
            onClick={() => setMobileRightOpen((v) => !v)}
            className="fixed bottom-20 right-3 z-30 flex size-11 items-center justify-center rounded-full bg-qiushi text-paper-card shadow-lg lg:hidden"
          >
            <FontAwesomeIcon icon={mobileRightOpen ? faXmark : faChartSimple} />
          </button>
          {mobileRightOpen && (
            <div className="fixed inset-0 z-40 lg:hidden">
              <div
                className="absolute inset-0 bg-ink-deep/40"
                onClick={() => setMobileRightOpen(false)}
              />
              <aside className="absolute bottom-0 right-0 top-12 w-72 overflow-auto border-l border-ink/20 bg-paper-card p-4 shadow-xl">
                <div className="mb-3 flex items-center justify-between">
                  <span className="font-serif text-sm font-bold tracking-widest text-ink-soft">
                    辅助面板
                  </span>
                  <button
                    onClick={() => setMobileRightOpen(false)}
                    className="text-ink-faint hover:text-ink"
                  >
                    <FontAwesomeIcon icon={faXmark} />
                  </button>
                </div>
                {rightPanel}
              </aside>
            </div>
          )}
        </>
      )}

      {/* === 移动端底栏导航（纸墨风） === */}
      <nav className="fixed bottom-0 left-0 right-0 z-30 flex border-t-2 border-double border-gold/30 bg-paper-deep/95 px-1 py-1.5 backdrop-blur lg:hidden">
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.end}
            className={({ isActive }) =>
              `flex flex-1 flex-col items-center gap-1 rounded-paper py-1 text-[11px] tracking-wider transition-colors ${
                isActive
                  ? "font-bold text-qiushi"
                  : "text-ink-soft hover:text-ink-deep"
              }`
            }
          >
            {({ isActive }) => (
              <>
                <KoboyoIcon name={item.icon} className="h-[18px] w-auto" />
                <span>{item.shortLabel ?? item.label}</span>
                <span
                  className={`h-0.5 w-5 rounded-full ${
                    isActive ? "bg-gold-bright" : "bg-transparent"
                  }`}
                />
              </>
            )}
          </NavLink>
        ))}
        {/* 移动端下载与设置入口 */}
        {FOOT_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            className={({ isActive }) =>
              `flex flex-1 flex-col items-center gap-1 rounded-paper py-1 text-[11px] tracking-wider transition-colors ${
                isActive
                  ? "font-bold text-qiushi"
                  : "text-ink-soft hover:text-ink-deep"
              }`
            }
          >
            {({ isActive }) => (
              <>
                <KoboyoIcon name={item.icon} className="h-[18px] w-auto" />
                <span>{item.label}</span>
                <span
                  className={`h-0.5 w-5 rounded-full ${
                    isActive ? "bg-gold-bright" : "bg-transparent"
                  }`}
                />
              </>
            )}
          </NavLink>
        ))}
      </nav>

      {/* === 全局浮动 AI 对话窗口 === */}
      <FloatingChat />
    </div>
  );
}

/** 辅助面板标题+内容包装器，保持各页面右栏风格统一 */
export function RightPanel({
  title,
  icon,
  children,
}: {
  title: string;
  icon?: IconName;
  children: ReactNode;
}) {
  return (
    <div>
      <h3 className="mb-3 flex items-center gap-2 font-serif text-sm font-bold tracking-[2px] text-ink-deep">
        {icon && <KoboyoIcon name={icon} className="h-4 w-auto text-gold" />}
        <span>{title}</span>
        <span className="h-px flex-1 bg-gradient-to-r from-ink/15 to-transparent" />
      </h3>
      {children}
    </div>
  );
}
