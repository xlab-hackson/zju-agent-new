import { Layout, RightPanel } from "../components/Layout.js";
import { ErrorState } from "../components/ErrorState.js";
import { Loading } from "../components/Loading.js";
import {
  useSemesters,
  useExams,
} from "../api/zju.js";
import { formatDateTime } from "../utils/format.js";
import { parseExamTimestamp } from "../utils/format.js";
import type { Exam, Semester } from "@zju-agent/core";
import { useMemo, useState } from "react";
import { KoboyoIcon } from "../components/ui/KoboyoIcon.js";
import { InkTag, PageHead, PaperCard, PaperEmpty } from "../components/ui/Paper.js";

/** 学在浙大学期名 → 教务网 xnxq01id */
function semesterToXnxq01id(name: string): string | null {
  const m = /^(\d{4}-\d{4})(春|夏|春夏|秋|冬|秋冬|短)$/.exec(name);
  if (!m) return null;
  const year = m[1]!;
  const term = m[2]!;
  const id = ["春", "夏", "春夏"].includes(term) ? "2" : "1";
  return `${year}-${id}`;
}

/** 合并子学期（春/夏→春夏），返回按最近在前排序的去重列表 */
function mergedSemesters(semesters: Semester[]): Semester[] {
  const byId = new Map<string, Semester>();
  for (const s of semesters) {
    const id = semesterToXnxq01id(s.name);
    if (!id) continue;
    const existing = byId.get(id);
    if (!existing) {
      byId.set(id, {
        ...s,
        name:
          id.endsWith("-1")
            ? `${id.slice(0, 9)}秋冬`
            : id.endsWith("-2")
              ? `${id.slice(0, 9)}春夏`
              : s.name,
      });
    }
  }
  return [...byId.values()].sort((a, b) => {
    const ax = semesterToXnxq01id(a.name)!;
    const bx = semesterToXnxq01id(b.name)!;
    return bx.localeCompare(ax);
  });
}

export function ExamsPage() {
  const { data: rawSemesters } = useSemesters();
  const semesters = useMemo(() => mergedSemesters(rawSemesters ?? []), [rawSemesters]);

  // 默认学期：时间最近
  const defaultId = useMemo(() => {
    return semesters[0] ? semesterToXnxq01id(semesters[0].name)! : undefined;
  }, [semesters]);

  const [selected, setSelected] = useState<string | undefined>(undefined);
  const xnxq01id = selected ?? defaultId;

  return (
    <Layout
      rightPanel={
        <RightPanel title="学期切换" icon="calendar-days">
          <select
            value={xnxq01id ?? ""}
            onChange={(e) => setSelected(e.target.value || undefined)}
            disabled={semesters.length === 0}
            className="ink-input"
          >
            {semesters.length === 0 && <option value="">（暂无学期）</option>}
            {semesters.map((s) => {
              const id = semesterToXnxq01id(s.name)!;
              return (
                <option key={id} value={id}>
                  {s.name}
                </option>
              );
            })}
          </select>
          <div className="mt-4 rounded-paper border border-gold/40 bg-gold/10 p-3.5 text-xs leading-relaxed text-ink-soft">
            <p className="mb-1.5 flex items-center gap-1.5 font-bold tracking-wide text-gold">
              <KoboyoIcon name="bell-notification" className="h-3.5 w-auto" />
              提醒规则（默认）
            </p>
            <p>考试前 1 天、2 小时、30 分钟各提醒一次。可在设置中调整。</p>
          </div>
        </RightPanel>
      }
    >
      <PageHead title="考试安排" sub="待考科目、考场与座位号" />

      {!xnxq01id ? (
        <PaperCard className="border-dashed">
          <PaperEmpty
            icon="exam-paper"
            title="未识别到任何学期"
            description="请先在学在浙大确认已选课。"
          />
        </PaperCard>
      ) : (
        <ExamsPanel xnxq01id={xnxq01id} />
      )}
    </Layout>
  );
}

function ExamsPanel({ xnxq01id }: { xnxq01id: string }) {
  const { data, isLoading, error, refetch, isFetching } = useExams(xnxq01id);
  const exams = data ?? [];
  const now = Date.now();

  const upcoming = exams
    .filter((e) => {
      const ts = parseExamTimestamp(e.time);
      return !Number.isNaN(ts) && ts >= now;
    })
    .sort((a, b) => parseExamTimestamp(a.time) - parseExamTimestamp(b.time));

  const past = exams
    .filter((e) => {
      const ts = parseExamTimestamp(e.time);
      return !Number.isNaN(ts) && ts < now;
    })
    .sort((a, b) => parseExamTimestamp(b.time) - parseExamTimestamp(a.time));

  const noTime = exams.filter((e) => !e.time || Number.isNaN(parseExamTimestamp(e.time)));

  if (error) {
    return (
      <>
        <ErrorState message={error.message} hint="请确认 ZJU 账号已验证，且教务网可访问。" />
        <button onClick={() => refetch()} className="btn-ink-outline mt-3 !px-3.5 !py-1.5 text-xs">
          重试
        </button>
      </>
    );
  }
  if (isLoading) return <Loading />;

  return (
    <div className="space-y-8">
      <div className="flex justify-end">
        <button
          onClick={() => refetch()}
          disabled={isFetching}
          className="btn-ink-outline !px-3.5 !py-1.5 text-xs"
        >
          {isFetching ? "刷新中…" : "刷新"}
        </button>
      </div>

      <Section juan="壹" title="待考科目" exams={upcoming} emptyText="本学期暂无待考科目安排" />
      <Section juan="贰" title="已结束" exams={past} emptyText="无已结束的考试" />
      <Section juan="叁" title="待安排时间" exams={noTime} emptyText="无待安排的考试" />
    </div>
  );
}

function Section({
  juan,
  title,
  exams,
  emptyText,
}: {
  juan: string;
  title: string;
  exams: Exam[];
  emptyText: string;
}) {
  return (
    <section>
      <h2 className="mb-3 flex items-center gap-2.5">
        <span className="juan-badge !px-2 !py-0.5 !text-[11px]">{juan}</span>
        <span className="font-serif text-base font-black tracking-[2px] text-ink-deep">
          {title}
        </span>
        <span className="font-mono text-xs text-ink-faint">({exams.length})</span>
        <span className="h-px flex-1 bg-gradient-to-r from-ink/15 to-transparent" />
      </h2>
      {exams.length === 0 ? (
        emptyText ? (
          <div className="px-1 text-xs tracking-wide text-ink-faint">{emptyText}</div>
        ) : null
      ) : (
        <div className="space-y-3">
          {exams.map((e) => (
            <ExamItem key={e.id} exam={e} />
          ))}
        </div>
      )}
    </section>
  );
}

function ExamItem({ exam }: { exam: Exam }) {
  const ts = parseExamTimestamp(exam.time);
  const now = Date.now();

  const badge = (() => {
    if (Number.isNaN(ts)) {
      return <InkTag tone="plain">时间待定</InkTag>;
    }
    if (ts < now) {
      return <InkTag tone="plain">已结束</InkTag>;
    }

    const diffMs = ts - now;
    const diffHours = Math.floor(diffMs / 3600_000);
    const diffDays = Math.ceil(diffMs / (24 * 3600_000));

    if (diffHours <= 24) {
      return (
        <InkTag tone="danger" dot>
          即将开考 · 仅剩 {Math.max(1, diffHours)} 小时
        </InkTag>
      );
    }
    if (diffDays <= 7) {
      return <InkTag tone="warn">近期待考 · 距今 {diffDays} 天</InkTag>;
    }
    return <InkTag tone="next">待考 · 距今 {diffDays} 天</InkTag>;
  })();

  return (
    <PaperCard interactive className="p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="truncate font-serif text-[15px] font-bold tracking-wide text-ink-deep">
            {exam.courseName}
          </div>
          {exam.semester && (
            <div className="mt-1 text-xs tracking-wide text-ink-soft">学期 {exam.semester}</div>
          )}
        </div>
        {badge}
      </div>
      <div className="mt-3 grid grid-cols-1 gap-2 rounded-paper border border-ink/10 bg-paper-deep/50 p-3 text-xs sm:grid-cols-3">
        <div>
          <div className="mb-1 text-[10px] tracking-[2px] text-ink-faint">考试时间</div>
          <div className="font-mono font-bold text-ink">{formatDateTime(exam.time)}</div>
        </div>
        <div>
          <div className="mb-1 text-[10px] tracking-[2px] text-ink-faint">地点</div>
          <div className="truncate font-bold text-ink">{exam.location || "待公布"}</div>
        </div>
        <div>
          <div className="mb-1 text-[10px] tracking-[2px] text-ink-faint">座位</div>
          <div className="font-mono font-bold text-ink">{exam.seat || "待公布"}</div>
        </div>
      </div>
    </PaperCard>
  );
}
