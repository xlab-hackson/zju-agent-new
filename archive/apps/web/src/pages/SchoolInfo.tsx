/**
 * 学校信息页：素质拓展平台 + 教务系统·通知公告。
 * 两个均为免登录公开源，由本地后端抓取并缓存；点击条目用系统浏览器打开原文。
 */

import { useMemo, useState } from "react";
import { Layout } from "../components/Layout.js";
import { ErrorState } from "../components/ErrorState.js";
import { Loading } from "../components/Loading.js";
import { useNotices } from "../api/zju.js";
import type { Notice, NoticeSource } from "@zju-agent/core";
import { Segmented } from "@crisp-ui-kit/crisp";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import {
  faRotate,
  faUpRightFromSquare,
} from "@fortawesome/free-solid-svg-icons";
import { KoboyoIcon } from "../components/ui/KoboyoIcon.js";
import { PageHead, PaperCard, PaperEmpty } from "../components/ui/Paper.js";

type SourceFilter = "all" | NoticeSource;

const SOURCE_FILTERS: { value: SourceFilter; label: string }[] = [
  { value: "all", label: "全部" },
  { value: "sztz", label: "素质拓展" },
  { value: "zdbk", label: "教务系统" },
];

/** 来源徽标配色：素拓竹青 / 教务朱红（对齐源站观感，融入纸墨色系） */
const SOURCE_BADGE: Record<NoticeSource, string> = {
  sztz: "border-bamboo/40 bg-bamboo/10 text-bamboo",
  zdbk: "border-seal/40 bg-seal/10 text-seal",
};

export function SchoolInfoPage() {
  const [source, setSource] = useState<SourceFilter>("all");
  const [refreshSeq, setRefreshSeq] = useState(0);
  const { data, isLoading, error, isFetching } = useNotices(20, refreshSeq);

  const failures = data?.failures ?? [];
  const filtered = useMemo(() => {
    const items = data?.items ?? [];
    return source === "all" ? items : items.filter((n) => n.source === source);
  }, [data, source]);

  return (
    <Layout>
      <PageHead
        title="学校信息"
        sub="素质拓展平台与教务系统的最新通知公告，点击条目在浏览器打开原文"
      />

      <div className="mb-4 flex items-center justify-between gap-3">
        <Segmented
          value={source}
          onValueChange={(val) => setSource(val as SourceFilter)}
          options={SOURCE_FILTERS.map((f) => ({
            value: f.value,
            label: (
              <span className="inline-flex items-center px-1 text-xs font-bold tracking-wide">
                {f.label}
              </span>
            ),
          }))}
        />
        <button
          onClick={() => setRefreshSeq((v) => v + 1)}
          disabled={isFetching}
          className="inline-flex items-center gap-1.5 text-sm tracking-wide text-ink-soft transition hover:text-gold disabled:opacity-50"
        >
          <FontAwesomeIcon
            icon={faRotate}
            className={`text-xs ${isFetching ? "animate-spin" : ""}`}
          />
          {isFetching ? "刷新中…" : "刷新"}
        </button>
      </div>

      {failures.length > 0 && (
        <div className="mb-4 flex items-start gap-2 rounded-paper border border-gold/45 bg-gold/10 px-3.5 py-2.5 text-xs leading-relaxed text-ink-soft">
          <KoboyoIcon name="bell-notification" className="mt-0.5 h-3.5 w-auto shrink-0 text-gold" />
          <span>{failures.join("；")}</span>
        </div>
      )}

      {error ? (
        <ErrorState
          message={error.message}
          hint="通知源可能暂时不可用，请稍后刷新重试。"
        />
      ) : isLoading ? (
        <Loading />
      ) : filtered.length === 0 ? (
        <PaperCard className="border-dashed">
          <PaperEmpty icon="announcement-horn" title="暂无通知" />
        </PaperCard>
      ) : (
        <ul className="space-y-2.5">
          {filtered.map((n) => (
            <NoticeRow key={n.id} notice={n} />
          ))}
        </ul>
      )}
    </Layout>
  );
}

function NoticeRow({ notice }: { notice: Notice }) {
  const open = () => window.open(notice.url, "_blank", "noopener");
  return (
    <li>
      <button
        onClick={open}
        className="paper-card group w-full px-4 py-3.5 text-left transition-all duration-200 hover:-translate-y-0.5 hover:border-qiushi/50 hover:shadow-paper-hover"
      >
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-1.5">
              {notice.important && (
                <span className="shrink-0 rounded-paper bg-seal px-1.5 py-0.5 text-[10px] font-bold tracking-widest text-paper-card">
                  置顶
                </span>
              )}
              <span
                className={`shrink-0 rounded-paper border px-1.5 py-0.5 text-[10px] font-bold tracking-wide ${SOURCE_BADGE[notice.source]}`}
              >
                {notice.sourceName}
              </span>
              <span className="truncate font-serif text-sm font-bold tracking-wide text-ink-deep transition-colors group-hover:text-qiushi">
                {notice.title}
              </span>
            </div>
            {notice.summary && (
              <p className="mt-1.5 line-clamp-2 text-xs leading-relaxed text-ink-soft">
                {notice.summary}
              </p>
            )}
            <div className="mt-2 flex items-center gap-3 font-mono text-[11px] text-ink-faint">
              {notice.date && <span>{notice.date}</span>}
              {notice.publisher && <span className="font-sans">{notice.publisher}</span>}
            </div>
          </div>
          <FontAwesomeIcon
            icon={faUpRightFromSquare}
            className="mt-1 shrink-0 text-xs text-ink-faint transition-colors group-hover:text-gold"
          />
        </div>
      </button>
    </li>
  );
}
