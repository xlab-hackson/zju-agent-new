import { useEffect, useState, useMemo } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { Layout } from "../components/Layout.js";
import { useAuthStatus } from "../api/auth.js";
import { useApiFetch } from "../api/bootstrap.js";
import { useAppSettings } from "../api/settings.js";
import {
  useCourses,
  useSemesters,
  useAllAssignments,
  useExams,
  useTimetable,
  useUpcomingSchedule48h,
} from "../api/zju.js";
import { Segmented } from "@crisp-ui-kit/crisp";
import { KoboyoIcon, type IconName } from "../components/ui/KoboyoIcon.js";
import {
  ChapterHead,
  InkTag,
  PaperCard,
  PaperEmpty,
  SealStamp,
} from "../components/ui/Paper.js";

/** 学在浙大学期名 → 教务网 xnxq01id */
function semesterToXnxq01id(name: string): string | null {
  const m = /^(\d{4}-\d{4})(春|夏|春夏|秋|冬|秋冬|短|短学期)$/.exec(name);
  if (!m) return null;
  const term = m[2]!;
  const year = m[1]!;
  if (term === "短" || term === "短学期") return `${year}-3`;
  return `${year}-${["春", "夏", "春夏"].includes(term) ? "2" : "1"}`;
}

interface ToolItem {
  title: string;
  description: string;
  icon: IconName;
  category: "study" | "life";
  to?: string;
  extUrl?: string;
  available?: boolean;
}

const TOOLS: ToolItem[] = [
  {
    title: "智云课堂",
    description: "课堂回放、课件下载与语音转文字检索",
    icon: "video-lesson-play",
    category: "study",
    to: "/classroom",
    extUrl: "https://classroom.zju.edu.cn",
    available: true,
  },
  {
    title: "学在浙大",
    description: "Canvas 平台、在线作业提交与教学通知",
    icon: "graduation-cap",
    category: "study",
    extUrl: "https://courses.zju.edu.cn",
    available: true,
  },
  {
    title: "本科生教务系统",
    description: "选课系统、培养方案、成绩单与考签查询",
    icon: "university",
    category: "study",
    extUrl: "http://jwbinfosys.zju.edu.cn",
    available: true,
  },
  {
    title: "CC98 论坛",
    description: "浙大学子专属的校内交流社区与论坛天地",
    icon: "comment-thread",
    category: "life",
    extUrl: "https://www.cc98.org",
    available: true,
  },
  {
    title: "校网充值与查询",
    description: "查询校网账户状态、剩余流量与快速充值",
    icon: "payment-card",
    category: "life",
    extUrl: "https://myvpn.zju.edu.cn",
    available: true,
  },
  {
    title: "图书馆座位预约",
    description: "各校区图书馆自习室座位与研修间实时预约",
    icon: "library-public",
    category: "life",
    extUrl: "http://libsys.zju.edu.cn",
    available: true,
  },
  {
    title: "校务综合服务大厅",
    description: "校车时刻表、学籍异动、用印申请与事务办理",
    icon: "school-building",
    category: "life",
    extUrl: "https://service.zju.edu.cn",
    available: true,
  },
  {
    title: "ETA 成绩分析",
    description: "专业排名、成绩与 GPA 换算分析",
    icon: "area-chart",
    category: "study",
    available: false,
  },
];

/** 今日日期条：干支年份感 + 公历 + 星期（报头用） */
function todayStrip(now: Date): { lunarish: string; dateEn: string; weekday: string } {
  const weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"];
  const months = [
    "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
    "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER",
  ];
  return {
    lunarish: `${now.getFullYear()} 年`,
    dateEn: `${months[now.getMonth()]} ${now.getDate()}`,
    weekday: weekdays[now.getDay()]!,
  };
}

export function DashboardPage() {
  const apiFetch = useApiFetch();
  const { data: authStatus, isLoading: authLoading } = useAuthStatus();
  const { data: rawSemesters } = useSemesters();
  const { data: courses } = useCourses();
  const { data: assignments, isLoading: assignmentsLoading } = useAllAssignments();
  const { data: exams, isLoading: examsLoading } = useExams();
  const { data: upcomingData, isLoading: scheduleLoading } = useUpcomingSchedule48h();

  const loggedIn = authStatus?.ok ?? false;
  const dateInfo = upcomingData?.dateInfo;

  // 个性化：昵称 / 头像（未设置时回落到学号）
  const { data: appSettings } = useAppSettings();
  const nickname =
    typeof appSettings?.nickname === "string" ? appSettings.nickname.trim() : "";
  const avatar =
    typeof appSettings?.avatarDataUrl === "string" ? appSettings.avatarDataUrl : undefined;
  const greetingName = nickname || (loggedIn ? authStatus?.username : undefined);

  // 获取模型设置状态
  const { data: settingsData, isLoading: settingsLoading } = useQuery({
    queryKey: ["settings"],
    queryFn: async () => {
      const res = await apiFetch("/api/settings");
      const json = await res.json();
      if (!json.ok) throw new Error(json.error?.message ?? "加载设置失败");
      return json.data as {
        modelProviders?: Array<{
          id: string;
          name: string;
          protocol: string;
          baseUrl: string;
          model: string;
          enabled: boolean;
        }>;
        credentials?: {
          hasZjuCredential: boolean;
          zjuUsernameMasked?: string;
          hasModelApiKey: boolean;
          modelProviderName?: string;
        };
      };
    },
  });

  const activeProvider =
    settingsData?.modelProviders?.find((p) => p.enabled) ??
    settingsData?.modelProviders?.[0];
  const hasModelConfigured =
    settingsData?.credentials?.hasModelApiKey || !!activeProvider?.name;

  // 倒计时刷新
  const [nowMs, setNowMs] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNowMs(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  // 筛选【本学期课程】
  const semesterMap = useMemo(
    () => new Map((rawSemesters ?? []).map((s) => [s.id, s])),
    [rawSemesters],
  );

  const currentSemesterId = dateInfo?.semesterId ?? "2026-2027-1";
  const { data: timetableEntries, isLoading: timetableLoading } = useTimetable(currentSemesterId);

  const timetableCourseCount = useMemo(() => {
    if (!timetableEntries || timetableEntries.length === 0) return 0;
    return new Set(timetableEntries.map((t) => t.courseName)).size;
  }, [timetableEntries]);

  const currentSemesterCourses = useMemo(() => {
    if (!courses) return [];
    return courses.filter((c) => {
      const sem = semesterMap.get(c.semesterId);
      if (!sem) return false;
      return semesterToXnxq01id(sem.name) === currentSemesterId;
    });
  }, [courses, semesterMap, currentSemesterId]);

  const totalCourseCount = timetableCourseCount > 0 ? timetableCourseCount : currentSemesterCourses.length;

  // 统计计算
  const activePending = (assignments ?? []).filter(
    (a) => !a.submitted && (!a.deadline || Date.parse(a.deadline) > nowMs),
  );
  const urgentAssignments = (assignments ?? []).filter((a) => {
    if (a.submitted || !a.deadline) return false;
    const due = Date.parse(a.deadline);
    return due > nowMs && due - nowMs < 48 * 3600 * 1000;
  });

  const assignments48h = useMemo(
    () => upcomingData?.assignments48h ?? [],
    [upcomingData],
  );

  const [upcomingTab, setUpcomingTab] = useState<"schedule" | "assignments">("schedule");

  const allPeriods = useMemo(() => {
    if (upcomingData?.allPeriods && upcomingData.allPeriods.length > 0) {
      return upcomingData.allPeriods;
    }
    if (upcomingData?.activePeriod) {
      return [upcomingData.activePeriod, ...(upcomingData.laterPeriods ?? [])];
    }
    return [];
  }, [upcomingData]);

  const upcomingAssignmentsList = useMemo(() => {
    if (assignments48h && assignments48h.length > 0) return assignments48h;
    return (assignments ?? [])
      .filter((a) => !a.submitted && (!a.deadline || Date.parse(a.deadline) > nowMs))
      .slice(0, 4)
      .map((a) => ({
        id: a.id,
        title: a.title,
        courseId: a.courseId,
        courseName: a.courseName,
        deadline: a.deadline ?? "",
        deadlineIso: a.deadline ? new Date(a.deadline).toISOString() : "",
        dueTimeStr: a.deadline
          ? new Date(a.deadline).toLocaleDateString("zh-CN", {
              month: "numeric",
              day: "numeric",
              hour: "2-digit",
              minute: "2-digit",
            }) + " 截止"
          : "无截止时间",
        remainingSeconds: a.deadline
          ? Math.max(0, Math.floor((Date.parse(a.deadline) - nowMs) / 1000))
          : 0,
      }));
  }, [assignments48h, assignments, nowMs]);

  const strip = todayStrip(new Date(nowMs));

  return (
    <Layout>
      <div className="mx-auto max-w-6xl pb-12">
        {/* === 报头：日期条 + 问候 + 学期签 + 落款印章 === */}
        <header className="mb-10">
          <div className="mb-3.5 flex items-center gap-3.5 font-mono text-xs tracking-[2px] text-gold">
            <span>{strip.lunarish}</span>
            <span>{strip.dateEn}</span>
            <span>{strip.weekday}</span>
            <span className="h-px min-w-16 flex-1 bg-gradient-to-r from-gold to-transparent" />
          </div>
          <div className="flex items-start justify-between gap-5">
            <div className="min-w-0">
              <div className="flex items-center gap-3.5">
                {avatar ? (
                  <img
                    src={avatar}
                    alt=""
                    className="size-12 shrink-0 rounded-full object-cover shadow-seal ring-2 ring-paper-card"
                  />
                ) : null}
                <h1 className="font-serif text-3xl font-black leading-tight tracking-[2px] text-ink-deep sm:text-4xl">
                  {greetingName ? (
                    <>
                      你好，
                      <span className="relative z-10 text-qiushi">
                        {greetingName}
                        <span
                          aria-hidden
                          className="absolute bottom-1 left-0 right-0 -z-10 h-2 bg-gold-bright/30"
                        />
                      </span>
                    </>
                  ) : (
                    "你好，浙大学子"
                  )}
                </h1>
              </div>
              <div className="mt-3.5 flex flex-wrap items-center gap-2">
                {dateInfo && (
                  <span className="inline-flex items-center gap-2 rounded-paper border border-ink/15 bg-paper-card px-3.5 py-1.5 text-[13px] tracking-wide text-ink shadow-seal">
                    {dateInfo.academicYear}学年 <b className="font-bold text-qiushi">{dateInfo.term}</b>
                    <span className="text-ink-faint">·</span>
                    {dateInfo.weekString}
                  </span>
                )}
                {dateInfo?.isHoliday && (
                  <InkTag tone="warn" dot>休：{dateInfo.holidayName ?? "放假"}</InkTag>
                )}
                {dateInfo?.isMakeupDay && (
                  <InkTag tone="next" dot>调：{dateInfo.holidayName}</InkTag>
                )}
                <InkTag tone="live" dot>教务已同步</InkTag>
              </div>
            </div>
            {/* 落款印章 */}
            <SealStamp size="lg" rotate={4} className="hidden shrink-0 sm:flex">
              浙大
              <br />
              助手
            </SealStamp>
          </div>
        </header>

        {/* === 卷一 · 接下来 === */}
        <section className="mb-10">
          <ChapterHead
            juan="卷一"
            title="接下来"
            sub="未来四十八小时 · 日程与待办"
            icon="cartoon-hourglass"
            right={
              <Segmented
                value={upcomingTab}
                onValueChange={(val) => setUpcomingTab(val as "schedule" | "assignments")}
                options={[
                  {
                    value: "schedule",
                    label: (
                      <span className="inline-flex items-center gap-1.5 px-1 text-xs font-semibold">
                        <span>日程</span>
                        {allPeriods.length > 0 && (
                          <span className="size-1.5 animate-pulse rounded-full bg-bamboo" />
                        )}
                      </span>
                    ),
                  },
                  {
                    value: "assignments",
                    label: (
                      <span className="inline-flex items-center gap-1.5 px-1 text-xs font-semibold">
                        <span>作业</span>
                        {assignments48h.length > 0 && (
                          <span className="rounded-paper bg-gold/20 px-1.5 text-[10px] font-bold text-gold">
                            {assignments48h.length}
                          </span>
                        )}
                      </span>
                    ),
                  },
                ]}
              />
            }
          />

          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            {scheduleLoading ? (
              <PaperCard className="col-span-1 p-8 text-center text-xs tracking-widest text-ink-faint md:col-span-2">
                <KoboyoIcon name="cartoon-hourglass" className="mx-auto mb-2 h-8 w-auto animate-pulse text-gold/60" />
                正在同步校历与日程时空流…
              </PaperCard>
            ) : upcomingTab === "schedule" ? (
              /* --- 日程列表 --- */
              allPeriods.length > 0 ? (
                allPeriods.map((period) => {
                  const startMs = new Date(period.startIso).getTime();
                  const endMs = new Date(period.endIso).getTime();
                  const isOngoing = nowMs >= startMs && nowMs <= endMs;
                  const liveSec = isOngoing
                    ? Math.max(0, Math.floor((endMs - nowMs) / 1000))
                    : Math.max(0, Math.floor((startMs - nowMs) / 1000));
                  const totalSec = Math.max(1, Math.floor((endMs - startMs) / 1000));
                  const progress = isOngoing
                    ? Math.min(100, Math.max(0, Math.floor(((nowMs - startMs) / 1000 / totalSec) * 100)))
                    : 0;

                  return (
                    <PaperCard
                      key={period.id}
                      interactive
                      className={`flex flex-col justify-between p-5 ${
                        isOngoing ? "border-bamboo/45 bg-bamboo/[.04] ring-1 ring-bamboo/25" : ""
                      }`}
                    >
                      <div>
                        <div className="mb-3 flex items-center justify-between gap-2">
                          <InkTag tone={isOngoing ? "live" : "next"} dot>
                            {isOngoing ? "正在进行" : "即将开始"}
                          </InkTag>
                          <span className="font-mono text-xs tracking-wide text-gold">
                            {period.friendlyTimeStr}
                          </span>
                        </div>

                        <div className="font-serif text-xl font-black tracking-wide text-ink-deep">
                          {period.title}
                        </div>
                        <div className="mt-2.5 flex flex-wrap items-center gap-2 text-xs text-ink-soft">
                          <span className="inline-flex items-center gap-1.5 rounded-paper bg-ink/[.06] px-2 py-1">
                            <KoboyoIcon name="map-location-pin" className="h-3 w-auto text-gold" />
                            {period.location}
                          </span>
                          {period.teacher && <span className="text-ink-faint">· {period.teacher}</span>}
                        </div>
                      </div>

                      <div className="mt-4 flex items-end justify-between border-t border-dashed border-ink/15 pt-3.5">
                        <div>
                          <div className="text-[10px] tracking-[3px] text-ink-faint">
                            {isOngoing ? "距 离 下 课" : "倒 计 时"}
                          </div>
                          <div
                            className={`mt-1 font-mono text-3xl font-bold leading-none tracking-[2px] ${
                              isOngoing ? "text-bamboo" : "text-qiushi"
                            }`}
                          >
                            {formatHMS(liveSec)}
                          </div>
                        </div>
                        {isOngoing && (
                          <div className="w-2/5">
                            <div className="mb-1 flex justify-between text-[10px] font-medium tracking-wider text-bamboo">
                              <span>课堂进度</span>
                              <span>{progress}%</span>
                            </div>
                            <div className="h-1.5 overflow-hidden rounded-full bg-ink/10">
                              <div
                                className="h-full rounded-full bg-[repeating-linear-gradient(-45deg,#2e7d32_0_6px,#3d9142_6px_12px)] transition-all duration-1000"
                                style={{ width: `${progress}%` }}
                              />
                            </div>
                          </div>
                        )}
                      </div>
                    </PaperCard>
                  );
                })
              ) : (
                <PaperCard className="col-span-1 md:col-span-2">
                  <PaperEmpty
                    icon="calendar-days"
                    title={
                      dateInfo?.weekString === "开学前夕" || dateInfo?.weekString === "假期"
                        ? `${dateInfo.weekString} · 四十八小时内暂无日程`
                        : "四十八小时内暂无待办日程"
                    }
                    description={`${dateInfo?.academicYear ?? ""}学年 ${dateInfo?.term ?? ""}（${dateInfo?.weekString ?? "今日"}）未来 48 小时内暂无课程或考试安排。`}
                  />
                </PaperCard>
              )
            ) : (
              /* --- 作业列表 --- */
              upcomingAssignmentsList.length > 0 ? (
                upcomingAssignmentsList.map((a) => {
                  const dueMs = a.deadline ? new Date(a.deadline).getTime() : 0;
                  const isUrgent = dueMs > 0 && dueMs - nowMs < 48 * 3600 * 1000;
                  const liveSec = dueMs > 0 ? Math.max(0, Math.floor((dueMs - nowMs) / 1000)) : 0;

                  return (
                    <PaperCard
                      key={a.id}
                      interactive
                      className={`flex flex-col justify-between p-5 ${
                        isUrgent ? "border-gold/55 bg-gold/[.05] ring-1 ring-gold/30" : ""
                      }`}
                    >
                      <div>
                        <div className="mb-2.5 flex items-center justify-between gap-2">
                          <InkTag tone="plain">
                            <span className="max-w-[176px] truncate">{a.courseName}</span>
                          </InkTag>
                          {dueMs > 0 && (
                            <InkTag tone={isUrgent ? "warn" : "plain"} dot={isUrgent}>
                              <span className="font-mono tracking-wider">{formatHMS(liveSec)}</span>
                            </InkTag>
                          )}
                        </div>
                        <div className="line-clamp-2 font-serif text-base font-bold leading-relaxed tracking-wide text-ink-deep">
                          {a.title}
                        </div>
                      </div>

                      <div className="mt-3.5 flex items-center justify-between border-t border-dashed border-ink/15 pt-3 text-xs text-ink-soft">
                        <span>截止：{a.dueTimeStr}</span>
                        <InkTag tone={isUrgent ? "danger" : "plain"}>
                          {isUrgent ? "48小时内紧急" : "待完成"}
                        </InkTag>
                      </div>
                    </PaperCard>
                  );
                })
              ) : (
                <PaperCard className="col-span-1 md:col-span-2">
                  <PaperEmpty
                    icon="checklist-paper"
                    title="近四十八小时暂无紧急待交作业"
                    description="所有待办作业均在安全期内或已全部提交完毕。"
                  />
                </PaperCard>
              )
            )}
          </div>
        </section>

        {/* === 卷二 · 学业快览（四联屏条） === */}
        <section className="mb-10">
          <ChapterHead juan="卷二" title="学业快览" sub="本学期核心学业统计" icon="area-chart" />
          <div className="grid grid-cols-1 overflow-hidden rounded-paper border border-ink/15 bg-paper-card shadow-paper sm:grid-cols-2 lg:grid-cols-4">
            <KpiTile
              to="/courses"
              label="本学期课程"
              icon="book-open"
              loading={timetableLoading}
              value={String(totalCourseCount)}
              unit="门"
              foot={dateInfo?.academicYear ? `${dateInfo.term}课表` : "每周课表"}
            />
            <KpiTile
              to="/assignments"
              label="待办作业"
              icon="checklist-paper"
              loading={assignmentsLoading}
              value={String(activePending.length)}
              unit="项待交"
              foot="截止一览"
              footTone="text-gold"
              alert={urgentAssignments.length > 0 ? `${urgentAssignments.length} 临近` : undefined}
            />
            <KpiTile
              to="/exams"
              label="考试安排"
              icon="exam-paper"
              loading={examsLoading}
              value={String(exams?.length ?? 0)}
              unit="场待考"
              foot="考场考签"
            />
            <KpiTile
              to="/downloads"
              label="下载中心"
              icon="folder"
              value="本地文库"
              valueSmall
              foot="课件与资料"
            />
          </div>
        </section>

        {/* === 卷三 · 校园百宝箱 === */}
        <section className="mb-10">
          <ChapterHead
            juan="卷三"
            title="校园百宝箱"
            sub="常用教务平台、校内生活与学术服务快捷直达"
            icon="scroll"
          />
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {TOOLS.map((tool) => {
              const isExt = !!tool.extUrl;
              const content = (
                <PaperCard
                  interactive={tool.available !== false}
                  className={`group flex h-full flex-col justify-between p-5 ${
                    tool.available === false ? "opacity-70" : ""
                  }`}
                >
                  <div>
                    <div className="mb-3.5 flex size-11 items-center justify-center rounded-paper border border-qiushi/60 bg-qiushi/5 text-qiushi transition-all duration-200 group-hover:-rotate-3 group-hover:bg-qiushi group-hover:text-paper-card">
                      <KoboyoIcon name={tool.icon} className="h-5 w-auto" />
                    </div>
                    <div className="mb-1.5 flex items-center justify-between gap-2">
                      <h3 className="font-serif text-[15px] font-black tracking-wide text-ink-deep transition-colors group-hover:text-qiushi">
                        {tool.title}
                      </h3>
                      {tool.available === false && (
                        <span className="shrink-0 rounded-paper border border-ink/20 px-1.5 py-0.5 text-[10px] tracking-widest text-ink-faint">
                          即将推出
                        </span>
                      )}
                    </div>
                    <p className="text-xs leading-relaxed tracking-wide text-ink-soft">
                      {tool.description}
                    </p>
                  </div>

                  {tool.available !== false && (
                    <div className="mt-4 flex items-center justify-between border-t border-dashed border-ink/15 pt-2.5 text-[11px] font-bold tracking-[2px] text-gold transition-transform group-hover:translate-x-0.5">
                      <span>{isExt ? "访问校内服务" : "进入功能"}</span>
                      <span>{isExt ? "↗" : "→"}</span>
                    </div>
                  )}
                </PaperCard>
              );

              if (tool.extUrl) {
                return (
                  <a
                    key={tool.title}
                    href={tool.extUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="block h-full"
                    title={`打开 ${tool.title}`}
                  >
                    {content}
                  </a>
                );
              }

              if (tool.to) {
                return (
                  <Link key={tool.title} to={tool.to} className="block h-full">
                    {content}
                  </Link>
                );
              }

              return (
                <div key={tool.title} className="block h-full">
                  {content}
                </div>
              );
            })}
          </div>
        </section>

        {/* === 卷四 · 系统与连接 === */}
        <section className="mb-6">
          <ChapterHead juan="卷四" title="系统与连接" sub="账号认证凭据与推理大模型状态" icon="key" />
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            {/* 1. 浙大统一身份认证状态 */}
            <PaperCard className="flex flex-col justify-between p-5">
              <div>
                <div className="mb-3 flex items-center justify-between gap-2">
                  <span className="text-xs font-bold tracking-[2px] text-ink-soft">
                    统一身份认证（ZJU）
                  </span>
                  <InkTag tone={authLoading ? "plain" : loggedIn ? "live" : "warn"} dot>
                    {authLoading ? "检测中…" : loggedIn ? "已登录" : "未登录"}
                  </InkTag>
                </div>
                <div className="truncate font-serif text-base font-bold tracking-wide text-ink-deep">
                  {loggedIn ? `账号：${authStatus?.username ?? "已认证"}` : "尚未绑定学号密码"}
                </div>
                <p className="mt-1.5 text-xs leading-relaxed text-ink-soft">
                  {loggedIn
                    ? "已连接学在浙大、教学教务与考场系统"
                    : "绑定后即可一键拉取课表、同步作业与考签"}
                </p>
              </div>
              <div className="mt-4 border-t border-ink/10 pt-3">
                <Link
                  to={loggedIn ? "/settings#zju" : "/setup"}
                  className="flex items-center justify-between text-xs font-bold tracking-wide text-qiushi hover:text-gold hover:underline"
                >
                  <span>{loggedIn ? "管理认证凭据" : "立即绑定账号"}</span>
                  <span>→</span>
                </Link>
              </div>
            </PaperCard>

            {/* 2. AI 模型 API 接口状态 */}
            <PaperCard className="flex flex-col justify-between p-5">
              <div>
                <div className="mb-3 flex items-center justify-between gap-2">
                  <span className="text-xs font-bold tracking-[2px] text-ink-soft">
                    大模型 API 接口
                  </span>
                  <InkTag
                    tone={settingsLoading ? "plain" : hasModelConfigured ? "live" : "danger"}
                    dot
                  >
                    {settingsLoading ? "检测中…" : hasModelConfigured ? "已就绪" : "未配置"}
                  </InkTag>
                </div>
                <div className="truncate font-serif text-base font-bold tracking-wide text-ink-deep">
                  {hasModelConfigured
                    ? (activeProvider?.name ??
                      settingsData?.credentials?.modelProviderName ??
                      "大模型服务")
                    : "暂无可用模型配置"}
                </div>
                <p className="mt-1.5 truncate text-xs leading-relaxed text-ink-soft">
                  {hasModelConfigured
                    ? `模型：${activeProvider?.model || "已连接到推理服务端"}`
                    : "配置 API Key 后即可开启全自动工具调用与对话"}
                </p>
              </div>
              <div className="mt-4 border-t border-ink/10 pt-3">
                <Link
                  to="/settings#providers"
                  className="flex items-center justify-between text-xs font-bold tracking-wide text-qiushi hover:text-gold hover:underline"
                >
                  <span>{hasModelConfigured ? "切换提供商与模型" : "前往配置 API Key"}</span>
                  <span>→</span>
                </Link>
              </div>
            </PaperCard>
          </div>
        </section>

        {/* === 页脚落款 === */}
        <footer className="mt-12 flex items-center justify-center gap-4 text-[11px] tracking-[3px] text-ink-faint">
          <span className="h-px w-20 bg-ink/15" />
          <span className="font-brush text-sm tracking-[5px] text-gold/80">浙江大学 · 求是校园助手</span>
          <span className="h-px w-20 bg-ink/15" />
        </footer>
      </div>
    </Layout>
  );
}

/** KPI 联屏格：四联条中的一格，整格可点进对应页面 */
function KpiTile({
  to,
  label,
  icon,
  value,
  unit,
  foot,
  footTone = "text-qiushi",
  alert,
  loading = false,
  valueSmall = false,
}: {
  to: string;
  label: string;
  icon: IconName;
  value: string;
  unit?: string;
  foot: string;
  footTone?: string;
  alert?: string;
  loading?: boolean;
  valueSmall?: boolean;
}) {
  return (
    <Link
      to={to}
      className="group flex flex-col justify-between border-b border-ink/15 p-5 transition-colors last:border-b-0 hover:bg-gold/[.06] sm:border-b sm:border-r sm:last:border-r-0 lg:border-b-0 lg:border-r lg:[&:nth-child(2)]:border-r-0 lg:[&:nth-child(4)]:border-r-0"
    >
      <div>
        <div className="flex items-center justify-between">
          <span className="text-xs font-bold tracking-[3px] text-ink-soft">{label}</span>
          <KoboyoIcon
            name={icon}
            className="h-[18px] w-auto text-qiushi transition-transform group-hover:-rotate-6 group-hover:text-gold"
          />
        </div>
        <div className="mt-3 flex items-baseline gap-1.5">
          <span
            className={`font-mono font-bold leading-none tracking-tight text-qiushi transition-colors group-hover:text-gold ${
              valueSmall ? "pt-1 font-serif text-2xl" : "text-5xl"
            }`}
          >
            {loading ? "…" : value}
          </span>
          {unit && <span className="text-xs tracking-wide text-ink-soft">{unit}</span>}
          {alert && (
            <span className="ml-1 self-center rounded-paper border border-seal/40 bg-seal/10 px-1.5 py-0.5 text-[10px] font-bold tracking-wider text-seal">
              {alert}
            </span>
          )}
        </div>
      </div>
      <div
        className={`mt-4 flex items-center justify-between border-t border-ink/10 pt-2.5 text-[11px] font-bold tracking-wide ${footTone} group-hover:underline`}
      >
        <span>{foot}</span>
        <span className="transition-transform group-hover:translate-x-0.5">→</span>
      </div>
    </Link>
  );
}

function formatHMS(totalSeconds: number): string {
  if (totalSeconds <= 0) return "00:00:00";
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}
