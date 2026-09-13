/**
 * 桌面挂件页面。
 *
 * 独立入口（widget.html），不套 Layout / Router / ServerStatusBanner：
 * - 数据只用一个接口 useUpcomingSchedule48h（48h 日程 + 待办作业，60s 自动刷新）
 * - 秒级倒计时在页面内本地计算，不增加网络请求
 * - 背景是纯 CSS 半透明：系统亚克力材质在「无边框 + 透明 + 置顶」窗口上只会渲染成
 *   纯灰 #545454（实测 Electron 33/38 均如此），详见 docs/widget-material-comparison.md
 * - 底部 AI 对话条走 mode=widget 一次性问答：只读工具 + 服务端强制简短回答
 */
import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import type { IconDefinition } from "@fortawesome/fontawesome-svg-core";
import {
  faArrowUpRightFromSquare,
  faCalendarCheck,
  faCircleNotch,
  faListCheck,
  faLocationDot,
  faPlugCircleXmark,
  faXmark,
} from "@fortawesome/free-solid-svg-icons";
import { formatDurationChinese } from "@zju-agent/core";
import type {
  AcademicDateInfo,
  UpcomingAssignment,
  UpcomingPeriod,
} from "@zju-agent/core";
import { useBootstrapStore } from "../api/bootstrap.js";
import { useBootstrap } from "../api/useBootstrap.js";
import { useUpcomingSchedule48h } from "../api/zju.js";
import { sectionRangeLabel } from "../utils/timetable.js";
import { WidgetChat } from "./WidgetChat.js";

/** 纯 CSS 半透明：桌面内容透出但不模糊（亚克力在本机置顶窗口上不可用） */
const PANEL_CLASS = "bg-slate-900/60 ring-1 ring-white/10";

const DRAG = { WebkitAppRegion: "drag" } as unknown as CSSProperties;
const NO_DRAG = { WebkitAppRegion: "no-drag" } as unknown as CSSProperties;

const WEEKDAYS = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];

function openInApp(pathname: string) {
  const api = window.electronAPI?.widget;
  if (api) void api.openApp(pathname);
  else window.open(pathname, "_blank");
}

function hideWidget() {
  void window.electronAPI?.widget.hide();
}

function formatHMS(totalSeconds: number): string {
  const total = Math.max(0, Math.floor(totalSeconds));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
}

function useNowTicker(): number {
  const [nowMs, setNowMs] = useState(() => Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNowMs(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  return nowMs;
}

// ---------------- 小组件 ----------------

function Header({
  title,
  dateInfo,
}: {
  title: string;
  dateInfo?: AcademicDateInfo;
}) {
  return (
    <div className="flex items-start justify-between gap-2 px-3.5 pb-2.5 pt-3" style={DRAG}>
      <div className="min-w-0">
        <div className="truncate text-[13px] font-semibold text-white">{title}</div>
        <div className="mt-0.5 truncate text-[10px] text-white/55">
          {dateInfo
            ? `${dateInfo.academicYear} 学年 ${dateInfo.term} · ${dateInfo.weekString}`
            : "浙大校园助手"}
        </div>
      </div>
      <button
        type="button"
        onClick={hideWidget}
        style={NO_DRAG}
        title="隐藏挂件（可从托盘图标重新显示）"
        className="shrink-0 rounded-md p-1 text-white/45 transition hover:bg-white/10 hover:text-white"
      >
        <FontAwesomeIcon icon={faXmark} className="text-[11px]" />
      </button>
    </div>
  );
}

function SectionTitle({
  icon,
  text,
  count,
}: {
  icon: IconDefinition;
  text: string;
  count?: number;
}) {
  return (
    <div className="mb-1 flex items-center gap-1.5 text-[10px] font-semibold tracking-wide text-white/45">
      <FontAwesomeIcon icon={icon} className="text-[9px]" />
      {text}
      {count !== undefined && <span className="text-white/30">{count}</span>}
    </div>
  );
}

function CenterHint({
  icon,
  text,
  spin,
}: {
  icon: IconDefinition;
  text: string;
  spin?: boolean;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 py-10 text-center">
      <FontAwesomeIcon
        icon={icon}
        className={`text-lg text-white/35 ${spin ? "animate-spin" : ""}`}
      />
      <span className="text-[11px] text-white/50">{text}</span>
    </div>
  );
}

function OngoingCard({ period, nowMs }: { period: UpcomingPeriod; nowMs: number }) {
  const startMs = Date.parse(period.startIso);
  const endMs = Date.parse(period.endIso);
  const remainSec = Math.max(0, Math.floor((endMs - nowMs) / 1000));
  const totalSec = Math.max(1, Math.floor((endMs - startMs) / 1000));
  const progress = Math.min(
    100,
    Math.max(0, Math.round(((nowMs - startMs) / totalSec) * 100)),
  );
  const section = sectionRangeLabel(period.startSection, period.endSection);

  return (
    <section className="rounded-xl bg-emerald-400/15 px-3 py-2.5 ring-1 ring-emerald-300/25">
      <div className="flex items-center gap-1.5 text-[10px] font-semibold text-emerald-300">
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
        正在进行
      </div>
      <div className="mt-1 truncate text-[13px] font-bold text-white">{period.title}</div>
      <div className="mt-0.5 truncate text-[10px] text-white/60">
        {section ? `${section} · ` : ""}
        {period.startTimeStr} - {period.endTimeStr} · {period.location}
        {period.teacher ? ` · ${period.teacher}` : ""}
      </div>
      <div className="mt-2 flex items-center justify-between text-[10px]">
        <span className="text-white/55">距离下课</span>
        <span className="font-mono text-[12px] font-semibold text-emerald-300">
          {formatHMS(remainSec)}
        </span>
      </div>
      <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-white/15">
        <div
          className="h-full rounded-full bg-emerald-400 transition-all duration-1000"
          style={{ width: `${progress}%` }}
        />
      </div>
    </section>
  );
}

function PeriodRow({ period }: { period: UpcomingPeriod }) {
  const section = sectionRangeLabel(period.startSection, period.endSection);
  return (
    <button
      type="button"
      onClick={() => openInApp("/courses")}
      className="w-full rounded-lg px-2.5 py-2 text-left transition hover:bg-white/10"
    >
      <div className="flex items-baseline justify-between gap-2">
        <span className="truncate text-[12px] font-medium text-white">{period.title}</span>
        <span className="shrink-0 text-[10px] text-white/50">{period.friendlyDateStr}</span>
      </div>
      <div className="mt-0.5 flex items-center gap-2 text-[10px] text-white/55">
        <span className="shrink-0">
          {section && <span className="mr-1 text-white/45">{section}</span>}
          <span className="font-mono">
            {period.startTimeStr}-{period.endTimeStr}
          </span>
        </span>
        <span className="truncate">
          <FontAwesomeIcon icon={faLocationDot} className="mr-0.5 text-[9px] text-white/35" />
          {period.location}
        </span>
      </div>
    </button>
  );
}

function AssignmentRow({
  assignment,
  nowMs,
}: {
  assignment: UpcomingAssignment;
  nowMs: number;
}) {
  const dueMs = assignment.deadlineIso ? Date.parse(assignment.deadlineIso) : NaN;
  const remainSec = Number.isNaN(dueMs)
    ? 0
    : Math.max(0, Math.floor((dueMs - nowMs) / 1000));
  const urgent = remainSec > 0 && remainSec < 24 * 3600;

  return (
    <button
      type="button"
      onClick={() => openInApp("/assignments")}
      className="w-full rounded-lg px-2.5 py-2 text-left transition hover:bg-white/10"
    >
      <div className="flex items-start justify-between gap-2">
        <span className="line-clamp-2 text-[12px] font-medium text-white">
          {assignment.title}
        </span>
        {remainSec > 0 && (
          <span
            className={`shrink-0 rounded px-1.5 py-0.5 font-mono text-[10px] ${
              urgent ? "bg-rose-500/25 text-rose-200" : "bg-white/10 text-white/60"
            }`}
          >
            {formatDurationChinese(remainSec)}
          </span>
        )}
      </div>
      <div className="mt-1 flex items-center justify-between gap-2 text-[10px] text-white/50">
        <span className="truncate">{assignment.courseName}</span>
        <span className="shrink-0">{assignment.dueTimeStr}</span>
      </div>
    </button>
  );
}

function Footer({
  updatedAt,
  onOpenApp,
}: {
  updatedAt: string | null;
  onOpenApp: () => void;
}) {
  const updated = updatedAt
    ? new Date(updatedAt).toLocaleTimeString("zh-CN", {
        hour: "2-digit",
        minute: "2-digit",
      })
    : "—";
  return (
    <div className="mt-auto flex items-center justify-between border-t border-white/10 px-3.5 py-2">
      <span className="text-[10px] text-white/40">更新 {updated}</span>
      <button
        type="button"
        onClick={onOpenApp}
        style={NO_DRAG}
        className="rounded-md px-1.5 py-0.5 text-[10px] text-white/60 transition hover:bg-white/10 hover:text-white"
      >
        打开应用
        <FontAwesomeIcon icon={faArrowUpRightFromSquare} className="ml-1 text-[9px]" />
      </button>
    </div>
  );
}

function ErrorCard({ message }: { message: string }) {
  return (
    <section className="rounded-xl bg-rose-500/15 px-3 py-2.5 ring-1 ring-rose-300/25">
      <div className="text-[11px] font-semibold text-rose-200">暂时无法获取日程</div>
      <div className="mt-1 break-words text-[10px] leading-relaxed text-white/60">
        {message}
      </div>
      <button
        type="button"
        onClick={() => openInApp("/settings")}
        className="mt-2 rounded-md bg-white/10 px-2 py-1 text-[10px] text-white/80 transition hover:bg-white/20"
      >
        检查账号设置
      </button>
    </section>
  );
}

// ---------------- 主体 ----------------

function ConnectedView() {
  const { data, isLoading, error } = useUpcomingSchedule48h();
  const nowMs = useNowTicker();

  const ongoing = useMemo(() => {
    const periods = data?.allPeriods ?? [];
    return periods.find(
      (period) =>
        nowMs >= Date.parse(period.startIso) && nowMs <= Date.parse(period.endIso),
    );
  }, [data, nowMs]);

  const nextPeriods = useMemo(() => {
    const periods = data?.allPeriods ?? [];
    return periods
      .filter((period) => Date.parse(period.startIso) > nowMs)
      .slice(0, 5);
  }, [data, nowMs]);

  const assignments = useMemo(() => (data?.assignments48h ?? []).slice(0, 4), [data]);

  const dateInfo = data?.dateInfo;
  const weekday = dateInfo ? (WEEKDAYS[dateInfo.weekday - 1] ?? "") : "";
  const title = dateInfo ? `${dateInfo.weekString} · ${weekday}` : "浙大校园助手";
  const empty = !ongoing && nextPeriods.length === 0 && assignments.length === 0;

  return (
    <>
      <Header title={title} dateInfo={dateInfo} />
      <div className="flex-1 space-y-2.5 overflow-y-auto px-3 pb-2">
        {isLoading && !data ? (
          <CenterHint icon={faCircleNotch} text="正在同步日程…" spin />
        ) : !data && error ? (
          <ErrorCard message={error.message} />
        ) : (
          <>
            {ongoing && <OngoingCard period={ongoing} nowMs={nowMs} />}

            {nextPeriods.length > 0 && (
              <section>
                <SectionTitle icon={faCalendarCheck} text="接下来" />
                <div className="space-y-0.5">
                  {nextPeriods.map((period) => (
                    <PeriodRow key={period.id} period={period} />
                  ))}
                </div>
              </section>
            )}

            {assignments.length > 0 && (
              <section>
                <SectionTitle icon={faListCheck} text="待办作业" count={assignments.length} />
                <div className="space-y-0.5">
                  {assignments.map((assignment) => (
                    <AssignmentRow
                      key={assignment.id}
                      assignment={assignment}
                      nowMs={nowMs}
                    />
                  ))}
                </div>
              </section>
            )}

            {empty && <CenterHint icon={faCalendarCheck} text="48 小时内没有安排" />}
          </>
        )}
      </div>
      <WidgetChat />
      <Footer updatedAt={data?.generatedAt ?? null} onOpenApp={() => openInApp("/")} />
    </>
  );
}

export function WidgetApp() {
  const { isReady, isConnected, error } = useBootstrap();
  const bootstrap = useBootstrapStore((s) => s.bootstrap);

  // 后端可能比挂件晚就绪（或中途重启），未连上时每 3 秒重试 bootstrap
  useEffect(() => {
    if (!isReady || isConnected) return;
    const timer = setInterval(() => void bootstrap(), 3000);
    return () => clearInterval(timer);
  }, [isReady, isConnected, bootstrap]);

  return (
    <div className="h-screen w-screen p-2">
      <div
        className={`flex h-full w-full flex-col overflow-hidden rounded-2xl shadow-2xl ${PANEL_CLASS}`}
      >
        {isConnected ? (
          <ConnectedView />
        ) : (
          <>
            <Header title="浙大校园助手" />
            <div className="flex flex-1 flex-col items-center justify-center gap-2 px-6 text-center">
              <FontAwesomeIcon
                icon={faPlugCircleXmark}
                className="text-xl text-white/40"
              />
              <div className="text-[12px] font-medium text-white/80">
                正在连接本地服务…
              </div>
              <div className="text-[10px] leading-relaxed text-white/50">
                {error ?? "请稍候，正在等待 127.0.0.1:7788 就绪"}
              </div>
            </div>
            <Footer updatedAt={null} onOpenApp={() => openInApp("/")} />
          </>
        )}
      </div>
    </div>
  );
}
