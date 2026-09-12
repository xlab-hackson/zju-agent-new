# AGENTS.md — 项目导航与协作约定

> 本文档按 2026-09-12 的实际代码状态维护，供后续编码助手快速定位当前实现、历史实现和验证方式。
> 本仓库正在从 React/Electron 客户端迁移到 Flutter 客户端。涉及界面、交互或本地数据时，默认以 `apps/flutter` 为当前实现；除非用户明确要求，不要为了 Flutter 需求修改旧的 `apps/web`。

## 1. 项目概览

**zju-campus-agent** 是本地优先的浙江大学校园智能助手，包含两套仍在仓库中的实现：

| 实现 | 当前定位 | 数据与服务方式 |
| --- | --- | --- |
| `apps/flutter` | **当前主实现**，Windows 桌面客户端，正在做迁移后的功能和界面验收 | Flutter 客户端直接访问校园服务、模型服务并使用本地 SQLite/安全存储 |
| `apps/web` + `apps/desktop` + `packages/*` | 旧的 React SPA/Electron/Node 实现，作为历史 Web 版本和参考实现保留 | React 通过本机 Fastify 服务访问 ZJU、LLM 和本地数据库 |

两套实现共享产品目标，但不是同一套运行时。旧实现中的约束、路径和数据目录不能直接套用到 Flutter。

安全边界仍然适用于整个项目：

- 不要把浙大密码、cookie 或模型 API key 写进日志、源码、提交记录或普通业务数据库。
- `login-zju` 只允许由旧 Node 服务端的 `packages/zju-services` 使用；Flutter 必须使用自己的协议实现，不得 import Node 包，也不得复制上游源码。
- Flutter 端的凭据只进入系统安全存储；校园 cookie 仅保存在内存中的分服务 cookie jar。
- 旧 Node 服务只绑定 `127.0.0.1`，默认端口 7788；这一点只属于旧 Web/Electron 运行链路。

## 2. 常用命令

### Flutter（当前主实现）

在 `apps/flutter` 目录执行：

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release
flutter test integration_test/native_storage_test.dart -d windows
```

真实浙大登录是手工验收项，不要在普通测试中自动提交账号密码：

```bash
flutter test tool/check_login_transport.dart
flutter test integration_test/native_login_test.dart -d windows --dart-define=VERIFY_SAVED_CAMPUS_LOGIN=true
```

Flutter 要求 Flutter >= 3.44、Dart >= 3.12。`pubspec.lock` 应提交。Windows 发布时必须保留完整的 `build/windows/x64/runner/Release`，包括 DLL 和 `data` 目录；本机需要 Visual Studio C++ Desktop workload 和 Windows SDK。

### 旧 Web/Electron/Node 实现

在仓库根目录执行：

```bash
pnpm install
pnpm dev:server
pnpm dev:web
pnpm typecheck
pnpm test
pnpm lint
pnpm build
pnpm --filter @zju-agent/web build
```

Windows 旧开发链路也可以使用根目录 `start-dev.bat` / `stop-dev.bat`。它们通过 `scripts/dev-launcher.mjs` 隐藏托管 Fastify、Vite 和 Electron 托盘/挂件；两个 bat 文件是 GBK + CRLF，修改时不要转换编码。

## 3. 仓库布局

```text
zju-agent-new/
├── AGENTS.md
├── CLAUDE.md
├── README.md                         # Flutter 当前实现简介、运行和安全说明
├── ZJU_CAMPUS_AGENT_PROJECT.md
├── apps/
│   ├── flutter/                      # 当前 Flutter 客户端
│   ├── web/                          # 旧 React SPA，勿因 Flutter 需求修改
│   └── desktop/                      # 旧 Electron 壳、托盘和挂件
├── packages/
│   ├── core/                         # 旧 Web/Node 共用领域类型和纯函数
│   ├── llm/                          # 旧 Node LLM 适配层
│   ├── server/                       # 旧 Fastify 服务
│   ├── zju-services/                 # 旧 Node login-zju 适配层
│   ├── storage/                      # 预留抽象
│   └── scheduler/                    # 预留抽象
└── docs/
```

根目录是 pnpm workspace（`apps/*`、`packages/*`）；`apps/flutter` 没有 `package.json`，不是 pnpm 包。

## 4. Flutter 当前架构

### 4.1 启动和路由

- `apps/flutter/lib/main.dart` 初始化 Flutter binding、`AppServices`、`DesktopHost` 和 Riverpod。
- 当前路由包括 `/`、`/courses`、`/assignments`、`/exams`、`/school-info`、`/downloads`、`/settings`、`/setup`、`/classroom`；`/dashboard`、`/toolbox`、`/chat` 仅是兼容别名并重定向到首页。
- `ui/pages/feature_page.dart` 仅负责路由到独立页面；工作台、课程表、作业、考试、通知、下载和课堂占位页各自在 `ui/pages/*_page.dart` 中管理状态。代码直接导入所属模块，不保留旧的集中导出入口；`ui/chat.dart` 是唯一在用的全局悬浮 AI 对话窗。
- 页面通用加载、首次刷新和缓存订阅位于 `ui/shared/campus_page.dart`；课表、课程辅助栏和详情位于 `ui/courses/`，作业、考试、下载与工作台组件分别位于 `ui/assignments/`、`ui/exams/`、`ui/downloads/`、`ui/dashboard/`。课程总览聚合与详情匹配位于 `application/course_overview.dart`、`application/course_details.dart`，页面数据加载器位于 `application/page_loaders/`；成绩计算、课程规范化、作业规则和小学期过滤位于 `domain/`，这些模块不依赖 UI。详细入口见 `apps/flutter/lib/ui/pages/README.md`。
- `ui/theme.dart` 集中定义宣纸色、卡纸色、墨色、蓝色、金色和印章色；不要在页面里重复创建一套颜色。

### 4.2 外壳与响应式行为

- `CampusShell` 以宽度 >= 1024 作为桌面布局：左侧导航栏宽 240；窄屏使用 AppBar、右上角下载/设置入口和底部导航。
- 桌面主窗口默认 1320×900，最小 800×600。
- 右侧辅助面板在宽屏显示；窄屏通过页面上的入口/FAB 调出底部面板。课程页保留这一行为；作业筛选已并入主内容，考试页不再保留冗余右栏。
- 页面首次进入时由 `AppServices.claimInitialRefresh(pageKey)` 控制本次应用运行内的一次**强制刷新**，避免手机端每次下拉通知栏或生命周期变化都重新请求。之后由用户主动刷新，手动刷新同样强制绕过缓存；学校信息页不使用下拉刷新。除本地下载页和占位页外，数据页使用一天有效的本地缓存，并在标题区域显示“数据更新于 N 分钟前”。
- 刷新/缓存约定：首次进入按稳定的 `pageKey` 只自动强制刷新一次；重复进入、路由重建和普通生命周期变化不自动请求。用户点击刷新或下拉刷新时必须强制请求最新数据。通知页使用两路独立的一天缓存，不提供下拉刷新但保留强制刷新按钮；下载页不参与网络数据缓存和更新时间提示。
- `CampusService` 按稳定缓存 key 合并并发请求：同一 key 在多个页面或多个 loader 同时读取时只允许产生一次实际网络请求，其他调用复用同一个 Future。成功写入缓存后通过 `cacheChanges` 广播资源变化；各页面按自己的依赖关系过滤事件，从缓存重新组合页面数据，不因跨页面通知再次强制联网。
- 更新时间属于缓存资源而不是某个页面请求。页面只聚合实际展示依赖的缓存记录；组合多个资源时取这些依赖中最早的更新时间，避免某一部分数据较旧却显示为刚刚更新。跨页面缓存通知应立即触发当前页面的本地重组，使共享数据的更新时间和内容实时同步。
- `CampusPageState.refresh` 和 `CourseOverviewState.refreshOverview` 在结束时同步更新刷新状态。辅助栏弹层是独立路由，通过 `overviewChanges` 与 `ListenableBuilder` 接收数据 Future、学期及刷新状态变化；仅对宿主页面调用 `setState` 无法保证已打开的弹层更新。通知器必须随页面释放。
- 工作台 loader 根据实际依赖资源的 `CampusService.stale` 状态提供 `_hasStaleData`。存在失败回退时，页面显示“部分数据未能刷新，当前仍包含上次成功获取的数据。”并保留真实缓存时间，不能用当前时间掩盖失败。
- 功能页标题默认只保留主标题；只有学校信息页保留解释性副标题。不要为了补充说明在标题旁重新添加小字。

### 4.3 工作台和卡片

- 首页学业快览与课程总览辅助栏共用 `loadCourseOverview` 的统一课程聚合结果：课程总览以教务网考签（`enrolledCourses('all')`）、全历史教务网课表和成绩库为权威来源，按规范化学期/课程名去重并补充学分、教师、成绩和绩点；学在浙大只负责课程建课状态及资料/作业关联。首页的课程数、学分和成绩统计不得再单独以另一份课程列表计算。
- 工作台通过一次 `upcoming()` 共享当前学期/相近学期的学期、课程、课表、作业和考试数据；学业快览仅在需要全历史成绩或全历史选课数据时额外读取 `grades('')` 与 `enrolledCourses('all')`，并把已有共享结果传给各 loader，避免首页重复请求。
- 待办作业拉取当前学期及相近学期作业，展示过滤规则：未到截止时间的全部显示；截止时间已过但未超过 1 周的继续显示；超过 1 周的不再展示。排序规则：未提交且未截止升序排在最前，未提交且截止未超 1 周的排在其后，已提交的作业排在最后。
- 统计卡当前是固定高度和统一内部节奏；下载管理卡必须与其他统计卡同高。窄屏时应优先压缩内容或换行，不要让 `Row` 溢出。
- 选中/悬停卡片的效果应是轻微浮起、阴影、边框和文字/图标颜色变化；默认背景保持纸张色，不要给整张卡片覆盖一层大面积选中颜色。
- 统计卡和百宝箱卡的默认图标主色为蓝色，悬停时才使用金色高亮。不可用的 ETA 卡不应伪装成可点击状态。
- **学业快览复合卡片重构（Academic Overview KPI Cards）**：
  - 4 张卡片当前维持统一 136px 固定高度、纸张底色与响应式布局（宽屏 4 列、中屏 2 列、窄屏 1 列）。高度定义在 `ui/pages/dashboard_page.dart` 的 `_kpiRow`。
  - **卡片 1（本学期学业）**：整合课程、学分与考试，从左到右依次排列**课程数**（点击打开当前学期的课程总览弹层）、**学分数**（展示当前学期选课学分，`onTap: null` 不跳转）、**考试数**（点击跳转至 `/exams`）。
  - **卡片 2（待办作业）**：细分为三分类状态一览，从左到右依次排列**将截止**（红色高亮，点击直达 `/assignments?tab=urgent`）、**还不急**（点击直达 `/assignments?tab=relaxed`）、**已提交**（绿色高亮，点击直达 `/assignments?tab=submitted`）。配合路由参数及 `initialAssignmentTab` 实现直达对应作业分类列表。
  - **卡片 3（学业成绩）**：依托教务网成绩全量数据与 `GradeStats` 引擎，从左到右依次排列**目前总绩点**（五分制加权 GPA）、**获得的总学分**（通过课程学分累计）、**百分制原始均分**（加权均分）；点击直接弹出辅助栏（`CourseRightPanel`，默认选中“全部学期”），在辅助栏内直观展示学业统计详情。
  - **卡片 4（下载中心）**：保留原本地文库入口与统一节奏。
  - **学分拉取与本学期选课学分聚合（与 Celechron 考签/选课实现对齐）**：
    - 正方教务网个人考签接口（`kscx_cxXsgrksIndex.html`）全年开放且包含学生当前学期全部已选课程及官方学分（`xf`）、课程号/选课课号（`xkkh`）；`CampusService.enrolledCourses()` 以此作为权威已选课程数据源，按选课课号与课程名去重累加学分与门数。
    - 修复了此前因部分进行中课程未排考导致条目被丢弃、以及由于存在 1 门出分极早的 1.5 学分短学期课导致未结课学期总选课学分被历史成绩覆盖的 bug；`GradeStats.compute` 强制优先使用权威已选课程/课表学分（`timetableCredits`）。
    - 辅助栏课程列表项（`CourseRightPanel`）与课程详情抽屉（`CourseDetailSheet`）元信息行中均支持展示学分标签（如 `4 学分`）。
- **日程卡片与头像交互体验优化**：
  - **移动端日程卡片紧凑排版**：窄屏（< 600px）下将课程名称与倒计时时分秒并入同一行（`Row`），彻底去除原“倒 计 时”与“距 离 下 课”冗余文字标签及分割线，仅保留清晰的倒计时时间（`formatHms`），并在其下方紧凑展示上课地点与任课教师。
  - **日程卡片点按交互**：日程卡片包裹 `InkWell` 点击事件（`CourseActions.openEventCourse`），点击时通过 `CourseDetails.enrichCourse` 对齐本地课表缓存，补充上课时间、教室与任课教师后弹出对应的课程详情抽屉（`CourseDetailSheet`）。
  - **头像防闪烁（Anti-flickering）**：`UserAvatar` 为 base64 数据新增内存字节缓存（`_avatarCache`），避免倒计时每秒触发局部刷新时反复解码导致闪烁；同时在外部包裹 `RepaintBoundary` 隔绝重绘蔓延。

### 4.4 课程表、辅助栏与考试

- 课程表界面（`TimetableView`）表头改版：
  - 清空原本卡片内部居中的“浙江大学课程表（...）”静态文本，改为表头行。
  - 左侧为 **Tab 切换学期** 胶囊按钮组：桌面端（宽屏 >= 700px）限制为表头一半宽度（`math.min(constraints.maxWidth * 0.5, constraints.maxWidth - 340.0)`），中间通过 `Spacer()` 与右侧操作按钮对齐；当学期 Tab 按钮较多或宽度不足时，根据真实字符/字号/内边距动态计算预估宽度（真实标签 ~160px，彻底废除旧的 `count * 95.0` 严重偏小估算），触发自适应模式使用 `_adaptiveSemesterTab`（动态内边距、字号并配合 `FittedBox` 缩放），使全部按钮自适应收敛在分配宽度内，非自适应模式移除导致溢出的硬编码 `ConstrainedBox` 并为 `_semesterTab` 补齐 `FittedBox`；窄屏（< 700px）右侧收缩为 108px 紧凑图标，左侧由 `Expanded` 弹性承载并支持水平平滑滑动，彻底杜绝所有窄窗/中等宽度下的 RenderFlex overflow。
  - 右侧集成操作按钮组：**导出图片**、**导出 Excel**、**刷新课表**。
    - 响应式自适应（`LayoutBuilder`）：宽屏（>= 700px）展示带文本与图标的操作按钮；窄屏/极限收窄（< 700px）自动收缩为紧凑的图标按钮（带 Tooltip 提示），右侧仅占约 108px，为左侧 Tab 留出最大空间，与左侧 `Expanded` 配合实现零溢出。
    - 空态体验：当前学期无课表数据时，课程表卡片依然完整保留该表头行（Tab 按钮与刷新按钮），下方展示空态，避免用户被困在空学期无法切回。
    - 导出图片优化：导出截图瞬间表头临时渲染居中正式标题“浙江大学课程表（$semester）”，导出完成后恢复 Tab 与操作按钮，保证导出长图美观无多余操作控件。
    - 课程表页面大标题（`PageHead`）净化：宽屏与窄屏下大标题均保持统一的“课程表”与更新时间，移除大标题处冗余的下拉框与刷新按钮。
  - 课程表与辅助栏结构分离与 Tab 联动同步：
    - 课程表下方遗留的静态课程目录已移除。
    - 课程表学期与右侧辅助栏（学期总览）Tab 切换联动同步：进入课程页时辅助栏初始与课程表同步为当前学期；在课程表表头或辅助栏切换具体学期时双向联动同步切换；辅助栏切换至“全部学期”时，课表保持当前学期不变；在辅助栏处于“全部学期”时切换课表学期，辅助栏同步切回该具体学期。两路的网络/缓存刷新机制独立触发。
    - 右侧辅助栏（`CourseRightPanel`）学期切换改版与任课老师：将原下拉选择框改为胶囊 Tab 切换按钮组，自适应按钮大小使得整体总宽度与总高度严格保持在两行以内（选项少于等于 2 项或单行空间充裕时单行展示，较多时均匀分成两行），选项采用 `FittedBox` 自适应文字缩放与统一 32px 紧凑高度，点击直接联动切换已选课程列表；通过重构的 `semesterDisplay` 精确识别秋学期（如 `2024-2025秋`）与冬学期（`2024-2025冬`），解决原本将秋/冬单学期误标为“秋冬”的 bug；每个课程项在课程名下方展示任课老师姓名（带 `Icons.person_outline` 紧凑图标）。
    - **全历史学期学分、教师与成绩/绩点穿透与学期隔离（Past Semesters Enrichment & Grade Badges）**：
      - 课程总览列表（`loadCourseOverview`）彻底停止使用学在浙大作为课程列表底座，完全改由**教务网（ZDBK：考签 `enrolledCourses('all')`、教务网课表 `timetable`、全历史成绩库 `grades('')`）**作为权威数据源，按 `(normSem, normName)` 规范化去重聚合。
      - **学在浙大建课状态关联、选课状态与页面承载（与 Celechron 选课对齐）**：
        - **选课状态确定性解耦（教务网 `sfqd` 权威驱动）**：
          - 彻底解耦学在浙大与选课状态/课表显示：教务网选课结果（`kbList`/`sjkList`/`enrolledCourses`）通过原生字段 `sfqd`（是否确定：`'1'` 已确定中签或预置课程，`'0'` 待筛选志愿）判定。学在浙大建课完全受教师开课驱动并严重滞后于选课筛选，不得将“未在学在浙大建课”当作未选中。
          - 考签接口（`kscx_cxXsgrksIndex.html`）任课教师从 `jsxm`/`jsxx` 正确提取，修复原本误将学生本人姓名 `xm` 当作教师名字的 bug。
        - 区分**已选中**（`selected: true`，默认教务网考签/课表/成绩权威源，且 `sfqd != '0'`）与**未选中**（`selected: false`，如 `sfqd == '0'` 待筛选志愿、退选课程或学在浙大存在但教务网未选中的旁听课程）：
          - 未选中的课程（包括 `sfqd == '0'` 的待筛选志愿）**绝不会出现在课程表（`TimetableView`）及工作台日程（`dailyEvents`）中**。
          - 辅助栏课程总览（`CourseRightPanel`）中未选中课程标注**“未选中”**徽标；课程详情抽屉（`CourseDetailSheet`）元信息行标注“未选中”，Tab 栏常驻“教务网未选中此课程”提示。
          - **已选中但未建课**的课程（`selected: true && learningZjuCreated: false`）正常在课程表和工作台日程展示，并在辅助栏与详情抽屉中展示**“未建课”**灰章徽标与“学在浙大无此课程”提示。
          - **已选中且已建课**的课程（`selected: true && learningZjuCreated: true`）正常在课程表展示，在辅助栏以典雅金色框线标注，无多余状态徽标。
          - 辅助栏课程排序规则：已选中已建课 -> 已选中未建课 -> 未选中课程，同类按名称字母排序。
          - 工作台学业快览与学业统计自动过滤未选课程，学分与门数统计仅计入已选中课程。
        - 所有课程均展示任课教师、上课时间并可点击唤起课程详情抽屉，其课程资料与作业对未建课或无课程 ID 的条目展示优雅空态。
      - **系列课程序号保留与规范化（Series Courses Distinction）**：通过 `cleanCourseExtraSuffix` 循环剥离末尾学期与教学班/选课号后缀，`normalizeCourseName` 精确对齐 1–5 系列（如将《计算机系统一》/《计算机系统Ⅰ》规范为 `计算机系统（1）`，将《计算机系统二》/《计算机系统Ⅱ》规范为 `计算机系统（2）`），彻底废除原粗暴剥离序号逻辑，保证不同系列课程绝不混淆、绝不互相覆盖。
      - **严格学期隔离（Semester Isolation Guard）**：成绩匹配时将学期与课程名复合（`$sem|$norm` 与 `$sem|$name`），未出分课程绝不向其他学期借用同名课程的历史成绩；同时增强 `semesterToId` 兼容解析 `2024-2025学年秋冬学期` 与 `2024-2025-1` 等多形态学期字符串，杜绝因学期解析失败导致的跨学期漂移。
      - 彻底解决过往学期由于仅查询单学期课表导致缺失学分与老师的问题：过往已结课课程自动从成绩单与考签提取官方学分与教师信息。
      - **已出分课程成绩与绩点徽标**：针对已出分的课程，通过 `formatGradeBadge` 格式化为 `92分 / 4.5`（数字分与绩点）或 `合格` / `优秀 / 4.5`（等级分），在课程项第一行右侧以典雅印章红胶囊徽标（`seal`）高亮展示；课程详情抽屉（`CourseDetailSheet`）元信息行中同步展示 `Icons.verified_outlined` 成绩与绩点标签。
    - **学业统计卡片集成与学期动态联动（Academic Stats Card in CourseRightPanel）**：
      - 在辅助栏学期 Tab 胶囊按钮组下方集成学业统计卡片（`_buildStatsCard`），依托 `domain/grade_stats.dart` 的 `computeSemesterGradeStats` 与教务网全量成绩库。
      - 统计指标包括：五分制加权绩点（已出分绿色高亮，未出分提示“修读中”或“--”）、获得与已选学分（如 `24 / 24` 或 `已选 24`）、百分制原始加权均分，以及底部课程门数与出分状态说明。
      - 切换学期 Tab（如从“全部学期”切换到具体过往学期或当前学期）时，统计卡片实时联动动态重新计算该学期的学业统计。
    - 辅助栏课程详情抽屉（`CourseDetailSheet`）：在课程名下方新增上课时间、地点教室与任课老师元数据信息行（`_buildCourseMetaRow`）；新增“作业”Tab，复用作业卡片样式展示课程所有作业（不分类）；辅助栏中作业卡片底色与资料卡片一致（`paper`），待办作业主页保持原卡纸色（`paperCard`）。
  - Flutter 课表使用 `ui/courses/timetable_view.dart` 中的 `TimetableView`：7 个日期列在可用宽度内自适应，课程内容区域可滚动；去除了原有内部单元格网格边框线（每节网格线），课程卡片直接展示在背景底色上保持整洁；当前纵向仍是 `Stack`/`Positioned` 加固定 52px 节次高度，且可视网格只绘制 1–13 节，因此“纵向内容自适应”仍是后续改造项。不要把这一现状误写成已经完全自适应，也不要在修复时继续扩大固定高度掩盖溢出。
    - **移动端与窄屏适配**：移动端下将左侧“节次/时间”列宽精简至 30px（表头显示“节次\n时间”，节次与时间文字紧凑靠左居中），节省出的 34px 横向空间全部分配给 7 天的课程色块；课程色块外边距收窄为 1px，左右内边距紧凑为 2px，显著拓宽色块净显示宽度；课程字体调至 8.5px，严格保证移动端一行显示 3 个字；课程名支持展示 3 行（`maxLines: 3`），格式化严格按每行 3 个字分行（杜绝 4-3-1 等怪异折行），超过 8 个字时自动规范截断为前 8 个字符后加省略号（3+3+2...），最多显示 8 个字再省略，兼顾小屏清晰识别与紧凑排版。
    - **秋/冬小学期分段切换**：在课程表表头下方提供“学期分段”胶囊按钮组（如秋冬学期提供“秋学期”、“冬学期”，春夏学期提供“春学期”、“夏学期”；不设“全部”选项以杜绝同一时段重叠课视觉冲突）。默认选中当前大学期的首个小学期；支持纯前端/本地快速切换，切换大学期时自适应重置；全学期通开课程（`subSemester` 为空或秋冬通开）在两段均予以保留；课程卡片周次文本同步展示小学期前缀（如“秋 1-8 周”），导出图片时正式标题联动携带分段后缀。
    - **课程色块点按交互**：课程色块包裹 `InkWell` 点击事件（`onSelectCourse` 回调），通过 `CourseActions.openTimetableCourse` 匹配课程列表并丰富上课时间、教室、教师属性后，调起对应课程详情抽屉。
- 课程产品的节次范围是 1–13 节，课表视觉网格当前也只画 1–13 节。`apps/flutter/lib/domain/schedule.dart` 的 `sessionTimes` 中第 14、15 项属于遗留的晚间时间数据，不得当作有效课程节次；后续应清理或明确隔离。旧 Web 仍使用 `packages/core/src/domain/schedule.ts`，两者不要混写。
- 课表、考试、成绩数据来自教务网；学在浙大主要提供课程、课件、作业和测验。
- 学校信息页直接读取素质拓展平台和教务网公开通知接口。`stripHtmlText` 必须在展示摘要前去掉 HTML 标签，并保留合理换行；教务发布人字段是 `xwfbr`。

## 5. Flutter 数据、认证与存储

### 5.1 服务容器和数据库

- `lib/application/services.dart` 的 `AppServices` 持有数据库、系统安全存储、校园服务、文件服务、备份服务和 Agent 服务。
- 数据库是 Drift + `NativeDatabase.createInBackground` 的 SQLite；数据库位于 `getApplicationSupportDirectory()` 下的 `agent.db`。测试使用 `AgentDatabase.memory()`。
- 缓存数据默认一天有效；页面本次运行第一次进入和用户手动刷新都会强制绕过缓存重新请求。网络失败时可以使用过期缓存并标记 `stale`，认证错误不可静默伪装成正常数据。
- `CampusService` 的 `_inflight` 按缓存 key 做请求去重，`cacheChanges` 是成功写入缓存后的跨页面广播流；页面订阅后应按实际依赖过滤并从缓存重载，不要把广播处理成新的强制网络刷新。
- 缓存更新时间用于页面显示“数据更新于 N 分钟前”；普通页面按实际展示依赖聚合更新时间，多个依赖取最早时间，不能用页面某次重组时间冒充数据更新时间。通知两个来源分别记录更新时间和失败状态，不能因单个来源失败覆盖另一个来源。
- 通知数据保留既有 `updatedAt` 兼容字段，同时使用统一的 `_updatedAt` 参与缓存时间聚合；校历和通知的来源时间必须独立维护。
- `CampusService.timetable` 遍历教务网响应的附加元数据时，先判断字段是否为列表，再处理其中的 Map 条目；缺失的 `sjkList` 按空列表处理。不要对每个响应字段直接调用 `rows()`，否则标量/对象字段会导致解析失败并回退旧缓存，表现为手动刷新后时间仍旧。
- 退出登录的目标行为是取消 Agent/下载相关活动、重置校园 session、清除内存 secret、缓存和待确认操作，并清空本次运行的首次刷新标记。当前 `AppServices.logout()` 已取消 Agent，但尚未调用 `FileService` 的下载取消入口；在补齐前不要宣称退出登录能中止所有进行中的下载。

### 5.2 浙大认证

- `data/campus_session.dart` 直接实现 ZJUAM、学在浙大和教务网的登录协议，凭据只读自 `FlutterSecureStorage`。
- CAS、课程和教务网分别持有内存 cookie jar，共用一次 ZJUAM 登录；请求遇到 401/403/901、登录 HTML 或重定向时识别为会话失效，并按服务重试一次。
- 手工重定向处理是有意设计：必须在跳转前保存 cookie；不要把认证跳转 URL、ticket、密码或 cookie 打进日志。
- 服务只接受 HTTPS 的 `zju.edu.cn` 子域名作为校园认证/数据跳转目标；模型服务另受 `ModelClient` 的 HTTPS/本地 HTTP 校验约束。
- 首页校园连接状态来自凭据存在性和 `CampusSession.authStatus`，不应每次进入首页都无条件做专门的状态探测；但工作台首次加载仍会调用课程/课表/作业/考试/48 小时日程加载器，是否真正联网由各数据缓存决定。首页“大模型 API 接口”卡片目前只表示存在模型来源配置，不等于已经通过实时可用性检测。

## 6. Flutter 文件下载与备份

- `application/files.dart` 使用本地 `downloads` 根目录，文件按课程建立子目录；文件名会清理非法字符，同名文件由系统式的 `file (1).ext` 处理。
- 学在浙大文件下载始终使用上传 `id`，不能把 `reference_id` 当成下载端点的 id。Office 文件预览可使用 `officePdf=true` 获取 PDF。
- 大文件下载先写入临时 `.part` 文件，完成后再原子改名；传输采用流式读取和背压，单文件上限 512 MB。删除前要取消对应活动流，不能让删除和重新下载争抢同一路径。
- 下载操作不应阻塞页面上的其他按钮；下载页的预览、打开、删除和重新下载状态必须独立管理。批量下载应复用同一套并发/取消/错误处理逻辑。
- 下载记录只存业务字段，不把数据库记录 ID 拼进文件名。
- `BackupService` 将 conversations、messages、settings、downloads、audit 打包；不包含 secrets、cookies、confirmations，并校验压缩包路径穿越和大小。

## 7. Flutter Agent、提示词和模型

### 7.1 Agent 与聊天

- `application/agent.dart` 是当前客户端 Agent：直接调用模型，工具覆盖课程、作业、课件、测验、日程、考试、课表、通知、成绩、知识库、下载以及实时界面感知（`zju_get_current_page_context`）。
- **页面感知功能（Page Context Awareness）**：
  - 由 `domain/page_context.dart` 的 `PageContext` 和 `PageApiGuide` 统一建模；`AppServices.currentPageContext` 全局响应式追踪。
  - 用户在工作台、课程表、待办作业、考试、通知、下载、设置等界面切换，或在课程表中切换学期、辅助栏学期、查看具体课程详情抽屉及其中的“课件资料”/“课程作业”Tab 时，界面上下文实时同步。
  - `AgentService.chat()` 与 `_run` 将当前界面上下文、辅助栏状态、当前查看课程/Tab、页面内容摘要以及**针对当前页面的推荐调用 API/工具指引（含建议参数如 `courseId`, `semester`）**自动注入大模型 System Prompt 中，使 Agent 在用户询问代词（如“这个课”、“作业什么时候交”）时能直接精准识别并调用对应 API，避免盲目猜测。
  - 开放只读工具 `zju_get_current_page_context` 供模型多轮迭代中显式获取最新界面状态。
- 普通聊天会话、消息和待确认操作落入本地数据库；挂件/小窗使用一次性只读模式，不持久化会话，不允许下载工具。
- 最多进行 8 轮模型/工具迭代。高风险操作需持久化确认，确认有效期 5 分钟。
- `ui/chat.dart` 的对话窗支持拖动标题栏、拖动边框/角改变大小、最小化和展开；发送键盘行为为 Enter 发送，Ctrl/Meta+Enter 换行。空白输入和空响应不能生成空消息卡片。
- 聊天窗必须是独立 overlay，不能用遮罩阻塞主界面；当前手机端是把同一个 overlay 的宽高限制在 SafeArea 可用空间内，并保留拖动/边框调整逻辑，还不是单独实现的底部面板。后续移动端验收要重点确认触控调整尺寸不会妨碍输入和主界面操作。

### 7.2 提示词资产

- 当前提示词资产是 `apps/flutter/assets/prompts.json`，由 `rootBundle.loadString(..., cache: false)` 加载并校验 `SYSTEM_PROMPT_TPL`、`GUIDE_RULES`、`BRIEF_RULES`。
- 资产缺失、JSON 无效或字段不完整时应报告明确的 `PROMPT_ASSET_*` 阶段错误；不要用静默空字符串掩盖资源打包问题，也不要把空响应当作正常回答。
- 修改提示词资产后同时检查 `pubspec.yaml` 的 assets 声明、运行目录和测试 binding。提示词加载问题优先排查资源路径/打包和字段校验，不要只改 UI 错误提示。

### 7.3 模型来源

- `ui/settings.dart` 中第一行模型下拉框表示当前来源，第二行表示协议；二者不能重叠或在视觉上像同一个字段。
- 每个来源包含用户可读的备注名、base URL、模型名、协议和安全存储的 API key；界面展示备注名，不直接拿模型名充当来源名。
- OpenAI 兼容协议通过 base URL 的 `/models` 读取可用模型；base URL 已含版本段时不能再无条件追加 `/v1`。Anthropic 使用手动模型名。
- “检测可用性”必须显示成功/失败结果，并且实际检测当前 base URL 和当前模型，而不是只做本地表单校验。API key 为空时应明确区分“保留已有 key”和“无法检测”。
- 修改模型请求拼接或检测逻辑时，覆盖无版本段、`/v1`、`/v4`、末尾斜杠和本地 HTTP 的测试。
- “大模型配置”和“个性化设置”卡片支持折叠与展开功能：头部包含折叠箭头与状态副标题，支持平滑高度过渡；默认收起以保持设置页紧凑，当未配置模型或处于首次向导时自动保持展开。

## 8. 个性化与桌面挂件

- `ui/avatar.dart` 提供默认圆形头像、文件选择和 data URL 压缩；设置页应直接显示圆形头像，首页顶部问候区和聊天头像复用同一设置。
- 个性化设置和其他应用设置一起整体保存；保存前必须展开已有设置，不能只 PUT 修改字段而清空下载目录等其他配置。
- `platform/desktop.dart` 是当前 Flutter Windows 桌面宿主，使用 `desktop_multi_window`、`window_manager` 和 `tray_manager`；它不是旧 Electron 实现。
- Flutter 挂件是透明无边框、置顶的小窗，显示未来 48 小时日程/待办并提供只读一次性问答。旧 Electron 挂件的材质结论只适用于 `apps/desktop`，不要据此给 Flutter 窗口引入 Electron API。

## 9. 旧 Web/Electron/Node 架构（仅供维护旧实现或对照）

以下内容仍对旧链路有效，但不是 Flutter 的实现说明：

- `apps/web` 是 React 18 + Vite + TanStack Query SPA；`apps/desktop` 是 Electron 壳；`packages/server` 是 Fastify 服务，默认监听 127.0.0.1:7788。
- 旧 Web 通过 `/api` 访问服务；`packages/server` 负责设置、认证、ZJU 课程/教务、通知、文件和 Agent SSE 路由。`packages/zju-services` 封装 `login-zju`。
- 旧 Web 的知识库是 `packages/server/knowledge/*.md`，由 `packages/server/src/knowledge` 检索并由 Electron extraResources 打包；Flutter 使用 `apps/flutter/assets/knowledge.json`，两套资产和加载器不同。
- 旧 Web 的课表时间源是 `packages/core/src/domain/schedule.ts`，课表网格是 `apps/web/src/components/TimetableGrid.tsx` 的 CSS Grid；不要把旧 Web 的组件直接搬进 Flutter。
- 旧 Web 的 `wrap()` 已有双层信封陷阱：`wrap(async () => ...)` 内返回原始值，不要再次返回 `ok(...)`。文件下载端点同样必须使用上传 `id`。
- 旧 Web 的凭据由 Node 端 AES-256-GCM 加密文件保存，旧数据目录通常为 `~/.zju-campus-agent/`；这不等于 Flutter 的 `getApplicationSupportDirectory()` 和系统安全存储。

## 10. 编码与修改约定

1. Flutter 代码保持 strict 分析通过；新增纯函数应配套测试，避免把网络、时区和文件系统逻辑直接塞进 widget。
2. 所有异步操作先完成异步工作，再同步 `setState`/更新 provider；不要把 `async` 闭包传给 Flutter `setState`。替换数据 Future 时使用同步语句块，不要让赋值表达式返回 Future；刷新完成后显式通知页面和已打开的辅助弹层。
3. 处理窄屏时优先使用 `Expanded`、`Flexible`、`Wrap`、滚动容器或约束内的文本截断；不要用任意增大固定高度掩盖 RenderFlex overflow。修改布局后至少检查桌面宽屏、800px 窄桌面和手机宽度。
4. 页面刷新要区分首次进入、手动刷新和应用生命周期变化；不要把生命周期回调直接当成每次请求入口。相同缓存 key 的并发读取必须复用请求，跨页面共享数据通过缓存变更广播实时同步。
5. 课程数、考试数等统计必须注明数据源；首页学业快览与课程总览必须复用统一聚合结果，不能把学在浙大课程列表和教务网课表混为同一份数据。
6. 页面更新时间只能来自实际展示依赖的缓存记录；组合数据取最早依赖时间，不能用请求完成时间或无关历史缓存时间覆盖它。
7. 资源文件改动要同步检查 `pubspec.yaml` 打包声明；不要用 fallback 空提示词掩盖资源缺失。
8. 不要执行破坏性 Git 操作（如 `git reset --hard`、覆盖用户未提交修改），除非用户明确要求。
9. 修改 `start-dev.bat` / `stop-dev.bat` 时保持 GBK + CRLF；不要用普通 UTF-8 编辑器直接保存。
10. 新增页面放在 `ui/pages/` 并独立管理状态；组件放入所属功能目录，页面数据组合放在 `application/page_loaders/`，纯业务规则放在 `domain/`。不要重新建立集中页面文件或兼容导出入口，业务模块不得反向依赖 UI。

## 11. 测试和验收

### Flutter

当前测试覆盖依赖兼容性、领域模型/课表、LLM URL 和请求、登录 cookie、认证协议、错误展示、SQLite/存储、作业筛选过滤、课程详情 Tab 及作业展示、课程表表头自适应/解耦/导出、课程表桌面端Tab半行自适应排版与窄屏滑动、课程表去网格框线、移动端课表尺寸精简与三行最多八字截断、秋/冬小学期分段过滤切换、右侧总览栏两行以内Tab自适应切换、秋/冬学期精准识别、课程表/日程点按弹出详情抽屉、课程详情上课时间/教室/教师元数据行、课程总览教师标注、移动端日程紧凑排版、设置页折叠展开、页面感知上下文与 API 指引、学业快览卡片直达与辅助栏学业统计、缓存请求合并、跨页面缓存通知和更新时间回归等；原生测试覆盖 Windows 安全存储和 SQLite，另有真实登录手工测试。

最近验证记录（2026-09-12）：页面拆分和旧入口删除后，`flutter test --no-pub` 为 105 项全通过，`flutter analyze --no-pub` 为 `No issues found!`。新增的 `test/feature_page_lifecycle_test.dart` 覆盖入口 key 不变时的路由切换、作业分类参数、首次/手动刷新、缓存广播、本地下载页和 1320/800/390px 下的七个功能页渲染。之后的课表解析、刷新结束状态、辅助弹层同步和旧数据提示修复按用户要求未再运行测试或分析，不能把这一检查点当作后续修复已经验证。

每次修改 Flutter 业务代码，优先执行：

```bash
cd apps/flutter
flutter test
flutter analyze
```

如果涉及资源、设置、下载、桌面宿主或真实校园接口，再补充相应的 Windows integration test 或手工验收。`flutter analyze` 当前可能报告若干 info 级风格/弃用提示；“无 error”与“退出码为 0”要分开记录，不能把 info 误报为全部通过。

### 旧 Web/Node

涉及旧链路时执行：

```bash
pnpm typecheck
pnpm lint
pnpm test
```

真实账号端到端测试仍需手工进行，并检查本地 `audit_logs` 不含密码、cookie、ticket 或 API key。

## 12. 当前项目状态与下一步判断

- Flutter 客户端已经覆盖认证、课程/课表、作业、考试、通知、下载、本地 Agent、模型设置、个性化和桌面挂件的主要路径；当前重点是迁移后的界面/交互与旧 Web 版本对齐，以及 Windows/手机响应式验收。
- Flutter 的 `/classroom` 当前只是占位页，百宝箱中的智云课堂、校网、图书馆等是外部链接；Flutter 代码中没有可用的 `ClassroomService`/`NetworkService`。旧 Node 包中的同名 stub 只属于历史实现，未经用户重新确认不要实现真实服务。
- 作业提交等超出当前已实现范围的功能，需要先确认服务端接口和产品范围，不要仅凭旧 Web 页面推断已支持。
- 任何“与 Web 完全一致”的需求都应先区分：用户是在比较旧 Web 视觉/交互，还是要求修改旧 Web 本身。默认只在 Flutter 实现对齐，保留用户明确要求保留的窄屏右上角设置/下载入口和辅助面板行为。

### 12.1 2026-09-11 全量扫描补充

以下扫描结论已纳入当前实现边界和后续验收清单；真实登录链路已由用户实测，本节不重复列为待验证项：

- 错误态：工作台和课程资料弹层仍有直接展示 `snapshot.error` 的路径；课程资料的 `FutureBuilder` 先判断 `!hasData`，请求失败时可能持续显示 loading。应改为脱敏、阶段化的错误状态。
- 刷新策略：页面首次进入由 `claimInitialRefresh(pageKey)` 控制一次强制刷新，手动刷新也强制绕过缓存；通知和校历已接入一天缓存。学校信息页不使用下拉刷新，但保留标题栏刷新按钮，并显示通知数据的更新时间。
- 下载页例外：它是本地文件管理页面，不走数据页首次进入刷新、网络缓存和更新时间提示；不要为了统一页面外观给下载页添加网络刷新逻辑。
- 退出登录：当前会取消 Agent 请求并重置校园会话，但没有统一取消 `FileService` 的活动下载；不能把退出登录描述成已中止所有后台文件传输。
- 提示词资产：`apps/flutter/assets/prompts.json` 已存在并声明在 `pubspec.yaml`，包含 `SYSTEM_PROMPT_TPL`、`GUIDE_RULES`、`BRIEF_RULES`，普通测试已覆盖。若运行时仍提示加载失败，应优先检查构建产物中的资源打包路径和缓存，不要用空字符串 fallback 掩盖问题。
- 响应式回归：本次扫描时尚未覆盖多宽度页面回归；后续 2026-09-12 的页面拆分已增加七个功能页在 1320/800/390px 下的渲染覆盖。设置、聊天窗、golden 和真机触控仍需继续验收。

### 12.2 2026-09-12 数据加载与页面联动

- 数据加载：`CampusService` 新增按缓存 key 的并发请求合并和 `cacheChanges` 广播；`upcoming()` 聚合工作台所需的相近学期数据，首页把共享结果传给作业、考试、课程和课表 loader，避免重复请求。
- 数据来源：课程总览和首页学业快览统一使用教务网考签、课表和全历史成绩聚合结果；学在浙大仅用于课程建课状态及课程资料/作业关联。新增选课学分、教师、成绩/绩点、短学期和历史学期隔离处理。
- 页面感知：新增 `domain/page_context.dart`，路由、学期、辅助栏、课程详情及资料/作业 Tab 都会实时同步到 `AppServices.currentPageContext`；Agent 可在提示词中使用上下文，也可通过 `zju_get_current_page_context` 主动读取。
- 界面与交互：课表表头 Tab/操作按钮响应式布局、导出、秋冬小学期切换、课程色块与日程卡片点按详情、课程详情元信息/作业 Tab、移动端紧凑排版、设置折叠和头像防闪烁均已纳入当前实现。
- 更新时间：页面按真实数据依赖聚合缓存时间，并订阅跨页面缓存变更后从缓存重组；课程辅助栏不再被无关的历史课表缓存时间污染，通知来源仍分别维护更新时间和失败状态。
- 验证：该阶段新增页面上下文、学业快览、缓存去重/广播和更新时间回归测试；当时 Flutter 全量测试 100 项通过，`flutter analyze` 无问题。
- Android 发布：校历公开接口是唯一显式允许的 `http://calendar.celechron.top` 明文例外，并有内置回退；Android release 当前仍使用 debug signing config，正式发布前必须补正式签名。

### 12.3 2026-09-12 页面模块拆分

- 原 6701 行集中页面实现已拆分，旧文件及兼容导出入口均已移除。七个页面分别管理状态，公共 UI、课程总览/详情、页面 loader 与领域规则按职责拆分；入口与测试直接导入对应模块。
- 缓存重组中的 `setState` 回调改为同步语句块，避免赋值表达式返回 `Future` 触发 Flutter 断言。
- 新增页面生命周期回归：不更换入口 key 的路由切换、作业分类参数、首次/手动刷新、缓存广播、下载页本地读取，以及 1320/800/390px 下的七个页面渲染。拆分后 `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 全量 105 项通过。

### 12.4 2026-09-12 手动刷新后仍显示旧时间的修复

- 课表解析跳过非列表元数据，仅处理列表中的 Map，并允许缺失 `sjkList`，避免响应附加字段导致解析失败后一直使用旧课表缓存。
- 页面和课程辅助栏刷新结束时显式更新状态；辅助弹层订阅 `overviewChanges`，同步数据 Future、学期、刷新状态和更新时间。
- 工作台根据实际缓存依赖显示部分刷新失败提示。组合时间仍取最早的真实依赖时间，失败回退不推进成功时间。
- 此阶段按用户要求未再运行测试、分析或手工验收；第 12.3 节的通过记录仅覆盖此前的页面拆分和旧入口删除。
