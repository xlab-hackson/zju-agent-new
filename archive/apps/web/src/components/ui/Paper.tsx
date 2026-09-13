import type { ReactNode } from "react";
import { KoboyoIcon, type IconName } from "./KoboyoIcon.js";

/**
 * 「求是书院 · 纸墨学术风」公共 UI 组件。
 * 视觉语言：暖白纸底、墨蓝正文、金色点缀、朱红印章、衬线/毛笔字体、
 * 直角小圆角（雕版感）、版印式硬阴影。
 */

/** 稿纸卡：所有面板的基底容器 */
export function PaperCard({
  children,
  className = "",
  interactive = false,
}: {
  children: ReactNode;
  className?: string;
  interactive?: boolean;
}) {
  return (
    <div
      className={`paper-card ${
        interactive
          ? "transition-all duration-200 hover:-translate-y-0.5 hover:shadow-paper-hover"
          : ""
      } ${className}`}
    >
      {children}
    </div>
  );
}

/** 卷章标题：蓝底卷签 + 衬线大字 + 副题 + 渐隐金线 */
export function ChapterHead({
  juan,
  title,
  sub,
  icon,
  right,
}: {
  /** 卷号，如「卷一」；不传则只显示标题 */
  juan?: string;
  title: string;
  sub?: string;
  icon?: IconName;
  right?: ReactNode;
}) {
  return (
    <div className="mb-4 flex items-center gap-3">
      {juan && <span className="juan-badge">{juan}</span>}
      {icon && (
        <KoboyoIcon
          name={icon}
          className="h-5 w-auto shrink-0 text-gold"
        />
      )}
      <h2 className="shrink-0 font-serif text-lg font-black tracking-[3px] text-ink-deep">
        {title}
      </h2>
      {sub && (
        <span className="hidden shrink-0 text-xs tracking-wide text-ink-faint sm:inline">
          {sub}
        </span>
      )}
      <span className="h-px flex-1 bg-gradient-to-r from-ink/20 to-transparent" />
      {right}
    </div>
  );
}

/** 朱文印章：毛笔字 + 朱红边框，微微旋转产生手盖章的随意感 */
export function SealStamp({
  children,
  size = "md",
  rotate = -3,
  className = "",
}: {
  children: ReactNode;
  size?: "sm" | "md" | "lg";
  rotate?: number;
  className?: string;
}) {
  const sizeCls =
    size === "lg"
      ? "size-16 text-base p-1.5"
      : size === "sm"
        ? "size-9 text-[11px]"
        : "size-12 text-sm";
  return (
    <div
      className={`seal-stamp opacity-90 shadow-seal ${sizeCls} ${className}`}
      style={{ transform: `rotate(${rotate}deg)` }}
    >
      <span className="text-center leading-tight">{children}</span>
    </div>
  );
}

/** 墨点状态签：live=竹青呼吸点 / next=求是蓝 / warn=金 / danger=朱红 / plain=墨 */
export function InkTag({
  tone = "plain",
  dot = false,
  children,
  className = "",
}: {
  tone?: "live" | "next" | "warn" | "danger" | "plain";
  dot?: boolean;
  children: ReactNode;
  className?: string;
}) {
  const toneCls = {
    live: "border-bamboo/40 bg-bamboo/10 text-bamboo",
    next: "border-qiushi/35 bg-qiushi/10 text-qiushi",
    warn: "border-gold/50 bg-gold/10 text-gold",
    danger: "border-seal/40 bg-seal/10 text-seal",
    plain: "border-ink/15 bg-ink/5 text-ink-soft",
  }[tone];
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-paper border px-2.5 py-0.5 text-[11px] font-bold tracking-[2px] ${toneCls} ${className}`}
    >
      {dot && (
        <span
          className={`size-1.5 rounded-full bg-current ${
            tone === "live" ? "animate-pulse" : ""
          }`}
        />
      )}
      {children}
    </span>
  );
}

/** 页内空状态：毛笔印章图案 + 说明文字 */
export function PaperEmpty({
  icon = "scroll",
  title,
  description,
}: {
  icon?: IconName;
  title: string;
  description?: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 px-6 py-10 text-center">
      <KoboyoIcon name={icon} className="h-10 w-auto text-ink/25" />
      <div className="font-serif text-base font-bold tracking-widest text-ink-soft">
        {title}
      </div>
      {description && (
        <div className="max-w-md text-xs leading-relaxed text-ink-faint">
          {description}
        </div>
      )}
    </div>
  );
}

/** 页面报头：卷首大字标题 + 说明（各内页顶部统一使用） */
export function PageHead({
  title,
  sub,
  right,
}: {
  title: string;
  sub?: string;
  right?: ReactNode;
}) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="font-serif text-2xl font-black tracking-[2px] text-ink-deep">
          {title}
        </h1>
        {sub && <p className="mt-1 text-xs tracking-wide text-ink-faint">{sub}</p>}
      </div>
      {right}
    </div>
  );
}
