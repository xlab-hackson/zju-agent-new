import { useState, useMemo, useRef } from "react";
import { Layout, RightPanel } from "../components/Layout.js";
import { ErrorState } from "../components/ErrorState.js";
import { Loading } from "../components/Loading.js";
import { TimetableGrid } from "../components/TimetableGrid.js";
import {
  useCourses,
  useSemesters,
  useMaterials,
  useDownloadMaterial,
  useTimetable,
} from "../api/zju.js";
import { formatBytes } from "../utils/format.js";
import {
  downloadTimetablePng,
  downloadTimetableXlsx,
  todayStamp,
} from "../utils/exportTimetable.js";
import { semesterDisplayName } from "../utils/timetable.js";
import type { Course, Semester } from "@zju-agent/core";
import { FontAwesomeIcon } from "@fortawesome/react-fontawesome";
import { faXmark } from "@fortawesome/free-solid-svg-icons";
import { KoboyoIcon, type IconName } from "../components/ui/KoboyoIcon.js";
import { PageHead, PaperCard, PaperEmpty } from "../components/ui/Paper.js";

/** 学在浙大学期名 → 教务网 xnxq01id */
function semesterToXnxq01id(name: string): string | null {
  const m = /^(\d{4}-\d{4})(春|夏|春夏|秋|冬|秋冬|短|短学期)$/.exec(name);
  if (!m) return null;
  const term = m[2]!;
  const year = m[1]!;
  if (term === "短" || term === "短学期") return `${year}-3`;
  return `${year}-${["春", "夏", "春夏"].includes(term) ? "2" : "1"}`;
}

/** 合并子学期，按最近在前排序 */
function mergedSemesters(semesters: Semester[]): Semester[] {
  const byId = new Map<string, Semester>();
  for (const s of semesters) {
    const id = semesterToXnxq01id(s.name);
    if (!id) continue;
    const existing = byId.get(id);
    if (!existing) {
      let displayName = `${id.slice(0, 9)}秋冬`;
      if (id.endsWith("-2")) displayName = `${id.slice(0, 9)}春夏`;
      else if (id.endsWith("-3")) displayName = `${id.slice(0, 9)}短学期`;
      byId.set(id, { ...s, name: displayName });
    }
  }
  return [...byId.values()].sort((a, b) => {
    const ax = semesterToXnxq01id(a.name) || "";
    const bx = semesterToXnxq01id(b.name) || "";
    return bx.localeCompare(ax);
  });
}

export function CoursesPage() {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const { data: rawSemesters, isLoading: semLoading } = useSemesters();
  const { data: courses, isLoading: coursesLoading, error } = useCourses();
  const semesters = useMemo(() => mergedSemesters(rawSemesters ?? []), [rawSemesters]);

  const defaultId = useMemo(() => {
    const foundCurrent = semesters.find((s) => semesterToXnxq01id(s.name) === "2026-2027-1");
    if (foundCurrent) return "2026-2027-1";
    return semesters[0] ? semesterToXnxq01id(semesters[0].name)! : undefined;
  }, [semesters]);

  const [selectedSem, setSelectedSem] = useState<string | undefined>(undefined);
  const xnxq01id = selectedSem ?? defaultId;

  // 按当前教务网 semesterId 匹配学在浙大课程
  const semesterMap = useMemo(
    () => new Map((rawSemesters ?? []).map((s) => [s.id, s])),
    [rawSemesters],
  );

  // 根据当前选择的学期 (xnxq01id) 过滤出对应课程
  const filteredCourses = useMemo(() => {
    if (!courses) return [];
    if (!xnxq01id || xnxq01id === "all") return courses;
    return courses.filter((c) => {
      const sem = semesterMap.get(c.semesterId);
      if (!sem) return false;
      return semesterToXnxq01id(sem.name) === xnxq01id;
    });
  }, [courses, xnxq01id, semesterMap]);

  const { data: timetableData, isLoading: timetableLoading } = useTimetable(
    xnxq01id && xnxq01id !== "all" ? xnxq01id : "",
  );
  const timetableCourseCount = useMemo(() => {
    if (!timetableData || timetableData.length === 0) return 0;
    return new Set(timetableData.map((t) => t.courseName)).size;
  }, [timetableData]);

  const grouped = useMemo(
    () => groupBySemester(filteredCourses, semesterMap),
    [filteredCourses, semesterMap],
  );

  return (
    <Layout
      rightPanel={
        <CoursesRightPanel
          semesters={semesters}
          xnxq01id={xnxq01id}
          selectedSem={selectedSem}
          onSemesterChange={(v) => {
            setSelectedSem(v);
            setSelectedId(null);
          }}
          grouped={grouped}
          totalCourses={filteredCourses.length}
          timetableCourseCount={timetableCourseCount}
          isLoading={semLoading || coursesLoading}
          timetableLoading={timetableLoading}
          errorMessage={error?.message}
          onSelectCourse={setSelectedId}
        />
      }
    >
      <PageHead title="课程表" sub="当学期课表与学在浙大课程资料" />

      {!xnxq01id ? (
        <PaperCard className="border-dashed">
          <PaperEmpty
            icon="calendar-grid"
            title="未识别到任何学期"
            description="请先在学在浙大确认已选课。"
          />
        </PaperCard>
      ) : xnxq01id === "all" ? (
        <PaperCard className="border-dashed">
          <PaperEmpty
            icon="calendar-days"
            title="已切换为「全部学期」总览"
            description="右侧总览已展示全部历史课程。课表按单学期排列，请在右侧选择具体学期查看当学期课程表。"
          />
        </PaperCard>
      ) : (
        <TimetablePanel xnxq01id={xnxq01id} />
      )}

      {selectedId && (
        <CourseDetailDrawer
          courseId={selectedId}
          onClose={() => setSelectedId(null)}
        />
      )}
    </Layout>
  );
}

/** 右栏：学期切换 + 课程列表总览 */
function CoursesRightPanel({
  semesters,
  xnxq01id,
  selectedSem,
  onSemesterChange,
  grouped,
  totalCourses,
  timetableCourseCount,
  isLoading,
  timetableLoading,
  errorMessage,
  onSelectCourse,
}: {
  semesters: Semester[];
  xnxq01id: string | undefined;
  selectedSem: string | undefined;
  onSemesterChange: (v: string | undefined) => void;
  grouped: ReturnType<typeof groupBySemester>;
  totalCourses: number;
  timetableCourseCount: number;
  isLoading: boolean;
  timetableLoading: boolean;
  errorMessage: string | undefined;
  onSelectCourse: (id: string) => void;
}) {
  return (
    <RightPanel title="学期总览" icon="scroll">
      {/* 学期切换 */}
      <div className="mb-4">
        <div className="mb-1.5 flex items-center justify-between">
          <label className="text-xs font-bold tracking-[2px] text-ink-soft">学期</label>
          <span className="font-mono text-[11px] text-ink-faint">
            {xnxq01id === "all"
              ? (isLoading ? "" : `全部课程 ${totalCourses} 门`)
              : (timetableLoading ? "" : `本学期 ${timetableCourseCount > 0 ? timetableCourseCount : totalCourses} 门`)}
          </span>
        </div>
        <select
          value={selectedSem ?? xnxq01id ?? ""}
          onChange={(e) => onSemesterChange(e.target.value || undefined)}
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
          <option value="all">全部学期（所有历史课程）</option>
        </select>
      </div>

      {/* 课程列表 */}
      {errorMessage ? (
        <div className="text-xs text-seal">加载失败：{errorMessage}</div>
      ) : isLoading ? (
        <div className="text-xs tracking-widest text-ink-faint">加载中…</div>
      ) : grouped.length === 0 ? (
        <div className="rounded-paper border border-dashed border-ink/20 bg-paper-deep/40 p-4 text-center text-xs tracking-wide text-ink-faint">
          该学期暂无学在浙大课程
        </div>
      ) : (
        <div className="space-y-4">
          {grouped.map((g) => (
            <div key={g.semesterId}>
              <div className="mb-1.5 flex items-center justify-between text-[11px] font-bold tracking-[2px] text-ink-soft">
                <span>{g.semesterName}</span>
                <span className="font-mono text-[10px] font-normal text-ink-faint">
                  {g.courses.length} 门
                </span>
              </div>
              <div className="space-y-1.5">
                {g.courses.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => onSelectCourse(c.id)}
                    className="w-full rounded-paper border border-ink/10 bg-paper-deep/40 px-2.5 py-2 text-left transition hover:border-qiushi hover:bg-paper-card hover:shadow-seal"
                  >
                    <div className="truncate text-xs font-bold text-ink">{c.name}</div>
                    {c.teachingClassName && (
                      <div className="truncate text-[10px] text-ink-faint">{c.teachingClassName}</div>
                    )}
                  </button>
                ))}
              </div>
            </div>
          ))}
          {xnxq01id !== "all" && timetableCourseCount > 0 && timetableCourseCount > totalCourses && (
            <div className="flex items-start gap-2 rounded-paper border border-gold/40 bg-gold/10 p-2.5 text-[11px] leading-relaxed text-ink-soft">
              <KoboyoIcon name="search-magnifier" className="mt-0.5 h-3.5 w-auto shrink-0 text-gold" />
              <span>
                教务网选课共 {timetableCourseCount} 门；右栏仅列出已在「学在浙大」开通课件空间的课程。
              </span>
            </div>
          )}
        </div>
      )}
    </RightPanel>
  );
}

function TimetablePanel({ xnxq01id }: { xnxq01id: string }) {
  const { data, isLoading, error, refetch, isFetching } = useTimetable(xnxq01id);
  const entries = data ?? [];

  // 导出：离屏渲染一份含标题的完整课表，供 PNG 截图（不受页面滚动裁剪）
  const exportRef = useRef<HTMLDivElement>(null);
  const [exporting, setExporting] = useState<"image" | "excel" | null>(null);
  const [exportError, setExportError] = useState<string | null>(null);
  const semesterLabel = semesterDisplayName(xnxq01id);
  const exportFileName = (ext: string) =>
    `课程表-${semesterLabel}-${todayStamp()}.${ext}`;

  const handleExportImage = async () => {
    if (!exportRef.current || exporting) return;
    setExporting("image");
    setExportError(null);
    try {
      await downloadTimetablePng(exportRef.current, exportFileName("png"));
    } catch {
      setExportError("图片导出失败，请重试。");
    } finally {
      setExporting(null);
    }
  };

  const handleExportExcel = async () => {
    if (entries.length === 0 || exporting) return;
    setExporting("excel");
    setExportError(null);
    try {
      await downloadTimetableXlsx(entries, semesterLabel, exportFileName("xlsx"));
    } catch {
      setExportError("Excel 导出失败，请重试。");
    } finally {
      setExporting(null);
    }
  };

  if (error) {
    return (
      <>
        <ErrorState message={error.message} hint="教务网课表接口可能调整，正在尝试兼容解析。" />
        <button onClick={() => refetch()} className="btn-ink-outline mt-3 !px-3 !py-1.5 text-xs">
          重试
        </button>
      </>
    );
  }
  if (isLoading) return <Loading />;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-end gap-4">
        {exportError && (
          <span className="mr-auto text-xs text-seal">{exportError}</span>
        )}
        <ToolButton
          icon="screen"
          onClick={handleExportImage}
          disabled={exporting !== null || entries.length === 0}
          label={exporting === "image" ? "生成中…" : "导出图片"}
        />
        <ToolButton
          icon="area-chart"
          onClick={handleExportExcel}
          disabled={exporting !== null || entries.length === 0}
          label={exporting === "excel" ? "生成中…" : "导出 Excel"}
        />
        <ToolButton
          icon="calendar-grid"
          onClick={() => refetch()}
          disabled={isFetching}
          label={isFetching ? "刷新中…" : "刷新"}
        />
      </div>
      {entries.length === 0 ? (
        <PaperCard className="border-dashed">
          <PaperEmpty icon="calendar-grid" title="该学期暂无课表数据" />
        </PaperCard>
      ) : (
        <>
          <TimetableGrid entries={entries} />
          {/* 离屏导出节点：完整宽度渲染标题+课表，仅在截图时被读取 */}
          <div aria-hidden className="pointer-events-none fixed -left-[9999px] top-0">
            <div ref={exportRef} className="w-[960px] bg-white p-4">
              <div className="mb-2 text-center text-base font-bold text-slate-900">
                浙江大学课程表（{semesterLabel}）
              </div>
              <TimetableGrid entries={entries} />
            </div>
          </div>
        </>
      )}
    </div>
  );
}

/** 工具栏小按钮（导出/刷新统一样式） */
function ToolButton({
  icon,
  onClick,
  disabled,
  label,
}: {
  icon: IconName;
  onClick: () => void;
  disabled?: boolean;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="inline-flex items-center gap-1.5 text-sm tracking-wide text-ink-soft transition hover:text-gold disabled:cursor-not-allowed disabled:opacity-40"
    >
      <KoboyoIcon name={icon} className="h-3.5 w-auto" />
      {label}
    </button>
  );
}

function CourseDetailDrawer({
  courseId,
  onClose,
}: {
  courseId: string;
  onClose: () => void;
}) {
  const { data: materials, isLoading, error } = useMaterials(courseId);
  const download = useDownloadMaterial();

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-ink-deep/40" onClick={onClose} />
      <div className="relative h-full w-full max-w-md overflow-auto border-l-2 border-double border-gold/40 bg-paper-card shadow-2xl">
        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-ink/15 bg-paper-deep px-5 py-3.5">
          <h3 className="flex items-center gap-2 font-serif text-base font-black tracking-[2px] text-ink-deep">
            <KoboyoIcon name="folders" className="h-4 w-auto text-gold" />
            课程资料
          </h3>
          <button onClick={onClose} className="text-ink-faint transition hover:text-seal">
            <FontAwesomeIcon icon={faXmark} />
          </button>
        </div>
        <div className="p-5">
          {isLoading ? (
            <Loading />
          ) : error ? (
            <ErrorState message={error.message} />
          ) : (materials ?? []).length === 0 ? (
            <PaperEmpty icon="folder" title="该课程暂无资料" />
          ) : (
            <ul className="space-y-3.5">
              {materials!.map((m) => (
                <li key={m.id} className="rounded-paper border border-ink/15 bg-paper p-3.5 shadow-seal">
                  <div className="mb-2 font-serif text-sm font-bold tracking-wide text-ink-deep">
                    {m.title}
                  </div>
                  {m.files.length === 0 ? (
                    <div className="text-xs text-ink-faint">无附件</div>
                  ) : (
                    <ul className="space-y-1.5">
                      {m.files.map((f) => (
                        <li key={f.id} className="flex items-center justify-between gap-2">
                          <div className="min-w-0 flex-1">
                            <div className="truncate text-xs text-ink">{f.name}</div>
                            <div className="font-mono text-[10px] text-ink-faint">{formatBytes(f.size)}</div>
                          </div>
                          <button
                            onClick={() =>
                              download.mutate({
                                courseId,
                                materialId: m.id,
                                fileId: f.id,
                                fileName: f.name,
                                officePdf: isOfficeFile(f.name),
                              })
                            }
                            disabled={download.isPending}
                            className="shrink-0 rounded-paper bg-qiushi px-2.5 py-1 text-[11px] font-bold tracking-wider text-paper-card shadow-seal transition hover:bg-qiushi-dark disabled:opacity-50"
                          >
                            下载
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                </li>
              ))}
            </ul>
          )}
          {download.isPending && (
            <div className="mt-3 text-xs tracking-wide text-ink-faint">下载中…</div>
          )}
          {download.isError && (
            <div className="mt-3 text-xs text-seal">下载失败：{download.error?.message}</div>
          )}
          {download.isSuccess && (
            <div className="mt-3 text-xs text-bamboo">已下载：{download.data.fileName}</div>
          )}
        </div>
      </div>
    </div>
  );
}

function groupBySemester(
  courses: Course[],
  semesterMap: Map<string, Semester>,
) {
  const groups = new Map<string, Course[]>();
  for (const c of courses) {
    const list = groups.get(c.semesterId) ?? [];
    list.push(c);
    groups.set(c.semesterId, list);
  }
  return [...groups.entries()]
    .map(([semesterId, list]) => ({
      semesterId,
      semesterName:
        semesterMap.get(semesterId)?.name ??
        (semesterId === "0" ? "其他 / 拓展课程" : semesterId),
      courses: list,
    }))
    .sort((a, b) => b.semesterName.localeCompare(a.semesterName));
}

function isOfficeFile(name: string): boolean {
  return /\.(docx?|pptx?|xlsx?)$/i.test(name);
}
