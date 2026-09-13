import { useMemo } from "react";
import { type TimetableEntry, mergeTimetableEntries } from "@zju-agent/core";
import {
  compressWeeks,
  courseNamesOf,
  groupTimetable,
  periodTimeRange,
  COURSE_COLORS,
  DAY_LABELS,
  DAYS,
  MAX_SECTION,
} from "../utils/timetable.js";

export function TimetableGrid({ entries: rawEntries }: { entries: TimetableEntry[] }) {
  const entries = useMemo(() => mergeTimetableEntries(rawEntries), [rawEntries]);
  const courseNames = useMemo(() => courseNamesOf(entries), [entries]);
  const colorOf = (name: string) =>
    COURSE_COLORS[courseNames.indexOf(name) % COURSE_COLORS.length]!;

  const groups = useMemo(() => groupTimetable(entries), [entries]);

  return (
    <div className="overflow-auto rounded-paper border border-ink/20 shadow-paper">
      {/*
        CSS Grid 显式定位：每个格子用 gridColumn/gridRow 精确放置，
        课程块通过 gridRow span 跨行，行高变化时块随网格线自然伸缩，
        不存在绝对定位手算高度导致的漂移。
        格子只画下边框+右边框，相邻线不重叠。
      */}
      <div
        className="grid bg-paper-card"
        style={{
          minWidth: 766,
          gridTemplateColumns: "64px repeat(7, minmax(0, 1fr))",
          gridTemplateRows: `32px repeat(${MAX_SECTION}, minmax(48px, auto))`,
        }}
      >
        {/* 表头（sticky 随横向滚动条吸顶）：深纸色 + 墨字 */}
        <div
          className="sticky top-0 z-20 flex flex-col items-center justify-center border-b border-r border-ink/20 bg-paper-deep p-1.5 text-[11px] font-bold leading-tight tracking-wider text-ink-soft"
          style={{ gridColumn: 1, gridRow: 1 }}
        >
          <span>节次</span>
          <span className="text-[9px] font-normal text-ink-faint">上课时间</span>
        </div>
        {DAYS.map((d) => (
          <div
            key={`h-${d}`}
            className="sticky top-0 z-20 flex items-center justify-center border-b border-r border-ink/20 bg-paper-deep p-1.5 font-serif text-xs font-bold tracking-[3px] text-ink"
            style={{ gridColumn: d + 1, gridRow: 1 }}
          >
            {DAY_LABELS[d]}
          </div>
        ))}

        {/* 节次编号列：节次 + 上课时间（时间来自 core 的浙大标准作息表） */}
        {Array.from({ length: MAX_SECTION }, (_, i) => i + 1).map((sec) => (
          <div
            key={`sec-${sec}`}
            className="flex flex-col items-center justify-center gap-0.5 border-b border-r border-ink/10 bg-paper-deep/50 px-0.5"
            style={{ gridColumn: 1, gridRow: sec + 1 }}
          >
            <span className="font-mono text-[11px] font-bold leading-none text-qiushi">
              {sec}
            </span>
            <span className="text-[9px] leading-none text-ink-faint">
              {periodTimeRange(sec)}
            </span>
          </div>
        ))}

        {/* 空白日格（负责画网格线） */}
        {DAYS.map((d) =>
          Array.from({ length: MAX_SECTION }, (_, i) => i + 1).map((sec) => (
            <div
              key={`cell-${d}-${sec}`}
              className="border-b border-r border-ink/10"
              style={{ gridColumn: d + 1, gridRow: sec + 1 }}
            />
          )),
        )}

        {/* 课程块：放在起始格，跨 span 行，随行高伸缩 */}
        {groups.map((g) => (
          <div
            key={`g-${g.weekday}-${g.startSection}`}
            className="z-10 flex min-w-0 gap-0.5 p-0.5"
            style={{
              gridColumn: g.weekday + 1,
              gridRow: `${g.startSection + 1} / span ${g.span}`,
            }}
          >
            {g.items.map((e) => (
              <div
                key={e.id}
                className={`min-w-0 flex-1 overflow-hidden rounded-paper border border-l-2 p-1.5 text-xs shadow-seal ${colorOf(e.courseName)}`}
              >
                <div className="truncate font-bold">{e.courseName}</div>
                {e.teacher && (
                  <div className="truncate text-[10px] opacity-70">{e.teacher}</div>
                )}
                {e.location && (
                  <div className="truncate text-[10px] opacity-70">{e.location}</div>
                )}
                {e.weeks.length > 0 && (
                  <div className="mt-0.5 font-mono text-[10px] opacity-50">
                    {compressWeeks(e.weeks)} 周
                  </div>
                )}
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
