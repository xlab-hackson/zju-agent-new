import { Layout, RightPanel } from "../components/Layout.js";
import { ErrorState } from "../components/ErrorState.js";
import { Loading } from "../components/Loading.js";
import {
  useAllAssignments,
  useCourseAssignments,
} from "../api/zju.js";
import {
  formatDateTime,
  deadlineUrgency,
} from "../utils/format.js";
import { sanitizeHtml } from "../utils/sanitizeHtml.js";
import type { Assignment } from "@zju-agent/core";
import { useState, useEffect } from "react";
import { useSearchParams } from "react-router-dom";
import { Segmented } from "@crisp-ui-kit/crisp";
import { KoboyoIcon } from "../components/ui/KoboyoIcon.js";
import { InkTag, PageHead, PaperCard, PaperEmpty } from "../components/ui/Paper.js";

const DEFAULT_URGENT_HOURS = 24;

export function AssignmentsPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const queryTab = searchParams.get("tab");
  const initialTab =
    queryTab === "urgent" || queryTab === "relaxed" || queryTab === "overdue" || queryTab === "submitted"
      ? queryTab
      : "urgent";

  const { data, isLoading, error, refetch, isFetching } = useAllAssignments();
  const [tab, setTab] = useState<"urgent" | "relaxed" | "overdue" | "submitted">(initialTab);

  useEffect(() => {
    if (queryTab === "urgent" || queryTab === "relaxed" || queryTab === "overdue" || queryTab === "submitted") {
      setTab(queryTab);
    }
  }, [queryTab]);
  const [urgentHours, setUrgentHours] = useState(DEFAULT_URGENT_HOURS);

  const all = data ?? [];
  const now = Date.now();
  const urgentThreshold = now + urgentHours * 3600_000;

  const overdue = all.filter(
    (a) => !a.submitted && a.deadline && Date.parse(a.deadline) <= now,
  );
  const urgent = all.filter(
    (a) => !a.submitted && a.deadline && Date.parse(a.deadline) > now && Date.parse(a.deadline) <= urgentThreshold,
  );
  const relaxed = all.filter(
    (a) => !a.submitted && a.deadline && Date.parse(a.deadline) > urgentThreshold,
  );
  const submitted = all.filter((a) => a.submitted);

  const list = tab === "urgent" ? urgent : tab === "relaxed" ? relaxed : tab === "overdue" ? overdue : submitted;

  return (
    <Layout
      rightPanel={
        <RightPanel title="分类设置" icon="cartoon-settings">
          <div className="space-y-4">
            <div>
              <label className="mb-2 block text-xs font-bold tracking-[2px] text-ink-soft">
                将截止阈值
              </label>
              <input
                type="range"
                min={1}
                max={72}
                value={urgentHours}
                onChange={(e) => setUrgentHours(Number(e.target.value))}
                className="w-full accent-qiushi"
              />
              <div className="text-center font-mono text-xs text-gold">
                距截止 ≤ {urgentHours} 小时
              </div>
            </div>
            <div className="space-y-2 rounded-paper border border-ink/10 bg-paper-deep/50 p-3 text-xs">
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-2 font-bold text-seal">
                  <KoboyoIcon name="bell-notification" className="h-3.5 w-auto" />
                  <span>将截止</span>
                </span>
                <span className="font-mono">{urgent.length} 项</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-2 font-bold text-gold">
                  <KoboyoIcon name="cartoon-hourglass" className="h-3.5 w-auto" />
                  <span>还不急</span>
                </span>
                <span className="font-mono">{relaxed.length} 项</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-2 font-bold text-ink-faint">
                  <KoboyoIcon name="scroll" className="h-3.5 w-auto" />
                  <span>已截止</span>
                </span>
                <span className="font-mono">{overdue.length} 项</span>
              </div>
              <div className="flex items-center justify-between border-t border-ink/10 pt-2">
                <span className="flex items-center gap-2 font-bold text-bamboo">
                  <KoboyoIcon name="checklist-paper" className="h-3.5 w-auto" />
                  <span>已提交</span>
                </span>
                <span className="font-mono">{submitted.length} 项</span>
              </div>
            </div>
          </div>
        </RightPanel>
      }
    >
      <PageHead
        title="待办作业"
        sub="按截止时间四态分类，右侧可调整「将截止」阈值"
        right={
          <button onClick={() => refetch()} className="btn-ink-outline !px-3.5 !py-1.5 text-xs">
            {isFetching ? "刷新中…" : "刷新"}
          </button>
        }
      />

      {/* 四分类 Tab（纸墨风段选器） */}
      <div className="mb-5 overflow-x-auto pb-1">
        <Segmented
          value={tab}
          onValueChange={(val) => {
            const nextTab = val as "urgent" | "relaxed" | "overdue" | "submitted";
            setTab(nextTab);
            setSearchParams({ tab: nextTab });
          }}
          options={[
            {
              value: "urgent",
              label: (
                <span className="inline-flex items-center gap-1.5 px-1 text-xs font-bold">
                  <span>将截止</span>
                  <CountChip tone="danger">{urgent.length}</CountChip>
                </span>
              ),
            },
            {
              value: "relaxed",
              label: (
                <span className="inline-flex items-center gap-1.5 px-1 text-xs font-bold">
                  <span>还不急</span>
                  <CountChip tone="warn">{relaxed.length}</CountChip>
                </span>
              ),
            },
            {
              value: "overdue",
              label: (
                <span className="inline-flex items-center gap-1.5 px-1 text-xs font-bold">
                  <span>已截止</span>
                  <CountChip tone="plain">{overdue.length}</CountChip>
                </span>
              ),
            },
            {
              value: "submitted",
              label: (
                <span className="inline-flex items-center gap-1.5 px-1 text-xs font-bold">
                  <span>已提交</span>
                  <CountChip tone="live">{submitted.length}</CountChip>
                </span>
              ),
            },
          ]}
        />
      </div>

      {error ? (
        <ErrorState message={error.message} hint="请确认 ZJU 账号已验证。" />
      ) : isLoading ? (
        <Loading />
      ) : list.length === 0 ? (
        <PaperCard>
          <PaperEmpty
            icon="checklist-paper"
            title={
              tab === "urgent"
                ? "暂无紧急作业"
                : tab === "relaxed"
                  ? "暂无常规作业"
                  : tab === "overdue"
                    ? "暂无逾期作业"
                    : "暂无已提交作业"
            }
            description="当前分类下没有相关作业记录。"
          />
        </PaperCard>
      ) : (
        <div className="space-y-3">
          {list.map((a) => (
            <AssignmentItem key={`${a.courseId}-${a.id}`} assignment={a} />
          ))}
        </div>
      )}

    </Layout>
  );
}

/** Tab 计数小签 */
function CountChip({
  tone,
  children,
}: {
  tone: "danger" | "warn" | "plain" | "live";
  children: React.ReactNode;
}) {
  const cls = {
    danger: "bg-seal/15 text-seal",
    warn: "bg-gold/20 text-gold",
    plain: "bg-ink/10 text-ink-soft",
    live: "bg-bamboo/15 text-bamboo",
  }[tone];
  return (
    <span className={`rounded-paper px-1.5 font-mono text-[10px] font-bold ${cls}`}>
      {children}
    </span>
  );
}

function AssignmentItem({ assignment }: { assignment: Assignment }) {
  const urgency = deadlineUrgency(assignment.deadline);
  return (
    <PaperCard interactive className="p-4">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="truncate font-serif text-[15px] font-bold tracking-wide text-ink-deep">
            {assignment.title}
          </div>
          <div className="mt-1 text-xs tracking-wide text-ink-soft">{assignment.courseName}</div>
        </div>
        {assignment.submitted ? (
          <InkTag tone="live">已提交</InkTag>
        ) : urgency !== "none" ? (
          <InkTag
            tone={urgency === "overdue" ? "danger" : urgency === "urgent" ? "warn" : "plain"}
            dot={urgency === "urgent"}
          >
            {urgency === "overdue" ? "已逾期" : urgency === "urgent" ? "即将截止" : "还不急"}
          </InkTag>
        ) : null}
      </div>
      <div className="mt-2.5 flex items-center gap-3 text-xs text-ink-soft">
        <span className="inline-flex items-center gap-1.5">
          <KoboyoIcon name="cartoon-hourglass" className="h-3 w-auto text-gold" />
          截止：<span className="font-mono">{formatDateTime(assignment.deadline)}</span>
        </span>
        {assignment.attachments.length > 0 && (
          <InkTag tone="plain">附件 {assignment.attachments.length}</InkTag>
        )}
      </div>
      {assignment.description && (
        <div
          className="mt-3 border-t border-dashed border-ink/15 pt-2.5 text-xs leading-relaxed text-ink [&_p]:mb-1"
          // 作业描述来自学在浙大富文本，必须经白名单消毒后再注入，防存储型 XSS
          dangerouslySetInnerHTML={{ __html: sanitizeHtml(assignment.description) }}
        />
      )}
    </PaperCard>
  );
}

/** 课程维度作业（预留入口，单课程查看用）。 */
export function CourseAssignmentsPanel({ courseId }: { courseId: string }) {
  const { data, isLoading, error } = useCourseAssignments(courseId);
  if (isLoading) return <Loading />;
  if (error) return <ErrorState message={error.message} />;
  return (
    <ul className="space-y-2">
      {(data ?? []).map((a) => (
        <AssignmentItem key={a.id} assignment={a} />
      ))}
    </ul>
  );
}
