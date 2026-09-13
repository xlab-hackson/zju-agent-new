# 浙江大学校园智能 Agent 项目开发文档

> 本文档按 2026-09-13 的实际代码状态更新。
> 它同时记录当前 Flutter 客户端的产品/技术规格，以及仓库中仍保留的旧 Web/Electron/Node 实现的维护边界。
> 后续涉及页面、交互、本地存储或桌面能力时，默认以仓库根目录的 Flutter 工程为准；除非用户明确要求，不要为了 Flutter 需求修改 `archive/apps/web`。

## 1. 文档范围与当前结论

本项目是一个本地优先的浙江大学校园智能助手。它从最初的 React Web + 本地 Node 服务方案，已经迁移到 Flutter 客户端作为当前主实现。仓库中旧的 React/Electron/Node 代码仍然有参考价值，但两套实现不是同一个运行时，也不应继续把旧方案的目录、API 和存储假设当成 Flutter 的实现细节。

当前 Flutter 客户端对外显示名称为**求是助手**；Android/Windows 的包名、应用 ID、技术目录和可执行文件名仍保留 `zju_campus_agent`，用于兼容现有构建和数据链路。

当前实现矩阵如下：

| 实现 | 目录 | 状态 | 适用场景 |
| --- | --- | --- | --- |
| Flutter 客户端 | 仓库根目录 | 当前主实现，Windows 正在功能和界面验收 | 新功能、页面调整、认证、下载、AI、桌面挂件 |
| React Web | `archive/apps/web` | 旧实现，保留作为历史 Web 版本和视觉/交互参考 | 明确要求维护 Web 版本时 |
| Electron + Node | `archive/apps/desktop`、`archive/packages/*` | 旧桌面运行链路 | 维护旧启动器、旧服务或对照行为时 |

### 1.1 当前已完成的主要路径

Flutter 客户端当前包含：

- 浙江大学统一身份认证、学在浙大和教务网会话管理。
- 学期、课程、课件/资料、作业、测验、教务网课表、考试和成绩查询。
- 素质拓展平台和教务网学校通知展示。
- 课程资料下载、按课程分类存储、预览、打开、删除、重新下载和批量下载。
- OpenAI 兼容协议和 Anthropic 模型来源配置。
- 当前模型检测，以及 OpenAI 兼容 base URL 的 `/models` 模型列表读取。
- 本地 Agent、工具调用、风险确认、会话历史和校园常识知识库检索。
- 头像/昵称等个性化设置，以及首页问候和聊天头像复用。
- Windows 系统托盘和显示未来 48 小时日程的桌面挂件；挂件展示 UI 对齐旧 Web，数据仍复用 Flutter 当前的 `upcoming()` 与只读 Agent 链路。
- 桌面端可拖动、可调整大小的悬浮 AI 对话窗；手机端的触控友好布局。

### 1.2 当前明确未完成或不应擅自扩大的范围

- Flutter 的 `/classroom` 当前只是占位页，百宝箱中的智云课堂、校网、图书馆等是外部链接；Flutter 代码中没有可用的 `ClassroomService`/`NetworkService`。旧 Node 包中的同名 stub 只属于历史实现，未经重新确认不要实现真实接口或支付流程。
- 作业提交不是当前 Flutter 已验收能力。旧规格中关于上传/提交的设计可作为未来规划，但不能对用户宣称已经支持。
- Android 可以继续维护跨平台兼容性，但当前尚未完成 Android 构建和全量功能验收。
- 旧 Web 的知识库、Fastify API、Electron 材质方案和 Flutter 的资源/运行方式相互独立，不要混用。

## 2. 产品目标与原则

### 2.1 产品目标

用户配置浙江大学账号和一个或多个模型来源后，可以在一个本地应用内完成：

1. 查看个人课程、课表、作业、考试、成绩和学校通知。
2. 查询并下载课程资料，管理本地文件。
3. 通过 AI 以自然语言查询校园数据和校园常识。
4. 对下载等可能产生资源或外部影响的操作进行可见、可拒绝的确认。
5. 在桌面和手机宽度下保持一致的信息层级和可操作性。

### 2.2 本地优先原则

- 当前 Flutter 客户端直接访问校园服务和模型服务，不依赖云端业务后端。
- 旧 Web/Electron 链路通过只绑定 `127.0.0.1` 的 Fastify 服务工作；它是历史实现的独立架构。
- 用户凭据、校园 cookie、模型 API key、聊天记录和下载记录默认留在本机。
- 不把密码、cookie、ticket、API key 或包含这些内容的 URL 写入日志、普通数据库、错误提示或 Git 提交。
- Agent 只能通过明确注册的工具访问校园功能，不允许模型自由拼接校园 URL 或绕过确认流程。

## 3. 参考项目与使用边界

### 3.1 login-ZJU / login-zju

参考项目：<https://github.com/5dbwat4/login-ZJU>

它是服务端 TypeScript 登录库，历史 Node 实现通过 npm 包 `login-zju` 使用。可参考的服务包括统一身份认证、学在浙大、教务网、智云课堂等。

约束：

- 不要把上游 `login-ZJU/` 源码目录复制进本仓库。
- 不要在 `archive/apps/web` 或 Flutter 中 import Node 包。
- 旧 Node 服务使用 `archive/packages/zju-services` 封装该 npm 包。
- Flutter 的 `data/campus_session.dart` 依照公开协议和已有实现重新完成客户端所需的认证流程，不复制上游源码。
- 登录跳转、RSA、服务票据、cookie 保存顺序和会话失效判断属于敏感逻辑，修改后必须增加协议测试或真实手工验收。

### 3.2 fiz

`fiz` 是学在浙大相关的 Vue + Vite + Tauri 工具，可参考课程、资料、作业、测试和下载接口的业务行为。

它不是本项目依赖。只参考接口路径、字段含义、解析方式和异常经验，不复制其 Rust/Tauri 架构、状态管理、组件或本地存储。

### 3.3 Celechron

Celechron 是教务网课程表/考试相关工具，可参考教务网请求参数、课程表结构、节次/周次/地点解析和异常处理。

它不是本项目依赖。Flutter 当前的教务网实现位于 `lib/data/campus_session.dart` 和 `lib/application/campus.dart`；旧 Web 实现使用 `archive/packages/zju-services`。

## 4. 总体架构

### 4.1 当前 Flutter 架构

```text
Flutter UI (lib/ui)
        │
        ├── Riverpod providers / AppServices
        │       │
        │       ├── CampusService
        │       │       └── CampusSession
        │       │               ├── ZJUAM / CAS
        │       │               ├── courses.zju.edu.cn
        │       │               └── zdbk.zju.edu.cn
        │       │
        │       ├── AgentService ── ModelClient ── OpenAI-like / Anthropic
        │       ├── FileService ─── 本地下载目录
        │       ├── BackupService
        │       └── AgentDatabase ─ Drift / SQLite
        │
        ├── FlutterSecureStorage ── 凭据和 API key
        └── DesktopHost ── Windows 窗口、托盘、桌面挂件
```

当前客户端没有 Node 业务 HTTP 服务。校园请求由 Flutter 中的 session/adapter 直接发出，模型请求由 Flutter 中的 `ModelClient` 发出。

### 4.2 旧 Web/Electron/Node 架构

```text
React UI (archive/apps/web)
        │ HTTP + 本地访问 token
        ▼
Fastify (archive/packages/server, 127.0.0.1:7788)
        ├── archive/packages/llm
        ├── archive/packages/zju-services ── login-zju
        ├── Agent / SSE / confirmation
        └── SQLite + 加密凭据 + 下载记录
```

旧架构继续保留是为了历史 Web 版本、旧桌面启动器和对照实现；它不是 Flutter 的依赖。旧架构的安全约束仍然有效，但不能据此推断 Flutter 需要本地 Fastify 或 `/api/bootstrap`。

## 5. 仓库结构与模块职责

```text
android/                         # Flutter Android 宿主
assets/                          # Flutter 资源、提示词和知识库
integration_test/
lib/                             # Flutter 应用源码
test/
tool/
windows/                         # Flutter Windows 宿主

archive/
├── apps/web/                    # 旧 React SPA 和 Web 挂件
├── apps/desktop/                # 旧 Electron 壳、托盘和挂件
├── packages/                    # 旧 Node workspace 包
└── scripts/                     # 旧开发脚本
```

### 5.1 Flutter 入口和路由

入口是 `lib/main.dart`，负责：

- 初始化 Flutter binding。
- 判断 Windows 主窗口或桌面挂件窗口。
- 创建 `AppServices` 和 `DesktopHost`。
- 初始化 Riverpod `ProviderScope`。
- 注册路由。

当前页面路由：

| 路径 | 页面 | 说明 |
| --- | --- | --- |
| `/` | 工作台 | 问候、48 小时日程、学业快览、百宝箱、连接状态 |
| `/courses` | 课程表 | 教务网课表、学期课程总览、资料入口 |
| `/assignments` | 作业 | 待办/临近截止/已截止等作业信息和筛选 |
| `/exams` | 考试 | 按学期展示考试安排 |
| `/school-info` | 学校信息 | 素质拓展和教务网通知 |
| `/downloads` | 下载管理 | 本地文件和下载记录 |
| `/settings` | 设置 | 认证、模型、个性化、目录和备份 |
| `/setup` | 配置向导 | 首次配置入口 |
| `/classroom` | 智云课堂占位页 | 当前为 stub |

`/dashboard`、`/toolbox`、`/chat` 是历史兼容别名，重定向到首页，不应重新创建独立旧页面。

### 5.2 Flutter 关键目录

- `application/services.dart`：数据库、凭据、校园服务、文件、备份和 Agent 的生命周期容器。
- `application/campus.dart`：校园领域调用、缓存、请求去重、跨页面缓存广播和数据源协调。
- `application/page_loaders/`：各页数据组合、实际缓存依赖及更新时间聚合；工作台共享 `upcoming()`，下载页只读取本地记录。
- `application/course_overview.dart`：首页和辅助栏共用的教务网课程总览聚合。
- `application/course_details.dart`：课程匹配、查找和课表元信息补全，不依赖 `BuildContext`。
- `application/files.dart`：下载、文件命名、目录隔离、预览、删除和备份。
- `application/agent.dart`：Agent 工具、确认、历史和模型循环。
- `application/llm.dart`：OpenAI 兼容/Anthropic 请求、模型列表和可用性检测。
- `application/knowledge.dart`：Flutter 知识库资产加载和检索。
- `data/campus_session.dart`：ZJUAM/CAS、课程和教务网 session、cookie 和请求保护。
- `data/credentials.dart`：`FlutterSecureStorage` 封装。
- `data/database.dart`：Drift 数据库和内存测试数据库。
- `domain/page_context.dart`：页面、学期、辅助栏、课程详情和推荐 API 指引的统一上下文模型。
- `domain/schedule.dart`：Flutter 当前节次、北京时间和校历投影逻辑。
- `domain/course_catalog.dart`、`grade_stats.dart`、`assignment_rules.dart`、`timetable_options.dart`、`formatters.dart`：课程规范化、成绩计算、作业规则、小学期筛选和格式化，不依赖 UI。
- `ui/pages/`：工作台、课程、作业、考试、学校信息和下载等独立页面；`feature_page.dart` 负责路由适配，各功能组件位于 `ui/` 下对应子目录。
- `ui/shared/campus_page.dart`：公共页面加载、错误状态、首次/手动刷新、缓存订阅和释放；不按路由分派业务。
- `ui/courses/`、`ui/assignments/`、`ui/exams/`、`ui/downloads/`、`ui/dashboard/`：所属功能的卡片、课表、辅助栏与详情弹层；跨功能通用组件和文件动作位于 `ui/shared/`。
- `ui/chat.dart`：唯一在用的全局悬浮 AI 对话窗。
- `ui/settings.dart`：认证、模型、个性化、备份和应用设置。
- `platform/desktop.dart`：Windows 主窗口、托盘和 Flutter 桌面挂件。

### 5.3 页面拆分与依赖边界

原 6701 行的集中页面实现及兼容导出入口已移除。`FeaturePage` 只把路由映射到独立页面，每个页面拥有自己的 State、筛选条件和页面上下文；路由切换不再依赖同一个 State 中的业务分支。

| 页面 | 入口（相对 `lib/ui/pages`） |
| --- | --- |
| 工作台 | `dashboard_page.dart` |
| 课程表 | `courses_page.dart` |
| 待办作业 | `assignments_page.dart` |
| 考试安排 | `exams_page.dart` |
| 学校信息 | `school_info_page.dart` |
| 下载中心 | `downloads_page.dart` |
| 智云课堂占位页 | `classroom_page.dart` |

工作台和课程页共用 `CourseOverviewState` 管理辅助栏，并通过 `CourseActions` 打开课程详情。页面只组合组件和管理交互，数据加载归 `application/page_loaders/`，课程聚合/匹配归 `application/`，纯规则归 `domain/`；业务模块不得反向依赖 UI。应用入口和测试直接导入所属模块，不重新建立集中导出文件。详细导航见 [Flutter 页面模块说明](lib/ui/pages/README.md)。

## 6. Flutter 技术栈与开发命令

### 6.1 技术栈

- Flutter >= 3.44，Dart >= 3.12。
- Flutter Riverpod 3、go_router 18、Dio、Drift、sqlite3。
- flutter_secure_storage、path_provider、file_picker、open_filex、url_launcher。
- flutter_markdown_plus、html、archive、excel。
- Windows 桌面使用 `desktop_multi_window`、`window_manager` 和 `tray_manager`。
- `pubspec.lock` 固定依赖版本，必须提交。

### 6.2 常用命令

在项目根目录执行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release
flutter test integration_test/native_storage_test.dart -d windows
```

Windows 发布包必须携带完整的 `build/windows/x64/runner/Release` 目录，包括 DLL 和 `data`；不能只复制 exe。构建需要 Visual Studio C++ 桌面开发工作负载和 Windows SDK。

合并代码后先执行 `flutter pub get`，同步本机包解析配置。服务字段/构造初始化变更后，热重载可能保留不兼容的旧实例；出现 `FileService._root` 空值类型异常时执行 Hot Restart（终端大写 `R`）或停止后重新启动。Windows 构建/原生测试若因运行中的同路径 EXE 报 `LNK1168`，先退出该客户端再重试。详见 [Flutter 开发排错](docs/flutter.md#开发排错)。

公开登录传输检查：

```powershell
flutter test tool/check_login_transport.dart
```

真实登录检查默认不进入普通自动测试。先在应用中保存真实凭据，再显式执行：

```powershell
flutter test integration_test/native_login_test.dart -d windows --dart-define=VERIFY_SAVED_CAMPUS_LOGIN=true
```

### 6.3 近期依赖约束

2026-09-11 已升级或切换：

- `go_router` 18.0.1
- `file_picker` 12.2.0
- `flutter_secure_storage` 11.1.0
- `drift`：`pubspec.yaml` 约束为 `^2.30.0`，当前 `pubspec.lock` 解析为 2.35.0
- `flutter_markdown_plus` 1.0.12
- 移除未使用的 `cookie_jar`

特殊约束：

- `file_picker` 12 的 `saveFile()` 会在平台侧写入字节；返回的 Android content URI 不能当成本地文件路径再次写入。
- `flutter_secure_storage` 不使用 v10 已废弃的加密配置；Android 最低 API 24，Windows 使用 DPAPI。
- `archive` 3.6.1 和 `xml` 6.6.1 暂保留，因为 `excel 4.0.6` 分别约束 `archive ^3.6.1` 和 `xml <7`；不能用 `dependency_overrides` 强行跨版本。
- `material_color_utilities` 和 `test_api` 的版本由当前 Flutter SDK 固定，`flutter pub outdated` 对它们的提示是预期现象。
- Android release 当前仍使用 debug signing config，只能视为开发/验收构建；正式发布前必须补充正式签名配置。

`pointycastle` 4.0.0 已在依赖声明和锁文件中，`domain/webvpn.dart` 使用其 AES 实现构造 WebVPN 链接；链接生成本身不读取用户凭据。2026-09-13 通过 `flutter pub get` 修复本机包解析配置缺失，未改动依赖版本或锁文件，链接与加密回归见 `test/webvpn_test.dart`。

## 7. 认证、校园服务和数据源

### 7.1 凭据与会话

`lib/data/campus_session.dart` 直接维护校园请求会话：

- 账号密码从 `FlutterSecureStorage` 读取，不进入 Drift 普通表。
- ZJUAM/CAS、学在浙大和教务网使用分开的内存 cookie jar。
- 统一认证成功后再按需建立课程或教务网服务会话。
- 手工处理重定向，确保在跳转前保存 cookie。
- 认证请求和服务请求不记录 URL 中的 ticket、密码、cookie 或完整响应。
- 仅允许 HTTPS 的 `zju.edu.cn` 子域名作为校园认证/数据跳转目标。
- 401、403、901、登录 HTML 或异常重定向应识别为会话失效，并按服务有限重试；不能把登录页 HTML 当作业务数据展示。
- `ensure` 采用 single-flight/串行保护，避免多个页面同时触发重复登录。

### 7.2 学在浙大数据

服务基址为 `https://courses.zju.edu.cn`，主要提供：

- 学期和课程列表。
- 课程资料/课件列表。
- 作业列表和作业状态。
- 测验列表。
- 文件上传元数据和资料下载。

文件模型同时可能包含上传 `id` 和 `reference_id`。下载端点必须使用上传 `id`，即 `f.id`；不能将 `reference_id` 误当成下载 id。

当前 Flutter 已实现资料读取和下载；作业提交相关旧规格仍属于未来能力，不能因为旧参考项目包含提交接口就默认接入。

### 7.3 教务网数据

服务基址为 `https://zdbk.zju.edu.cn/jwglxt`，主要提供：

- 学期映射。
- 学期课表。
- 考试安排。
- 成绩。

Flutter 课表使用教务网 `kbcx/xskbcx_cxXsKb.html` 端点，并按秋/冬、春/夏等子学期解析和合并条目。解析附加元数据前先检查字段是否为列表，只处理其中的 Map；缺失的 `sjkList` 按空列表处理，避免把响应中的标量或对象误当列表导致解析失败、回退旧课表缓存。

首页课程数量来自统一课程总览中当前学期的聚合结果：

```text
教务网考签 + 全历史课表 + 全历史成绩
                 │
                 ▼
     loadCourseOverview 规范化/去重/补全
                 │
        ┌────────┴────────┐
        ▼                 ▼
   首页学业快览       课程总览辅助栏
```

`CampusService.enrolledCourses('all')` 的教务网考签数据提供全历史已选课程和官方学分；教务网课表补充教师、时间、地点和当前课表信息；`grades('')` 补充已出分课程的成绩与绩点。`loadCourseOverview` 按规范化学期和课程名聚合，并保留系列课程序号、严格隔离不同学期的同名课程。

学在浙大课程列表只用于关联建课状态以及资料、作业和测验；未建课课程仍可展示教务网课程详情，但不应发起无谓的学在浙大资料请求。首页学业快览与课程总览必须复用同一份聚合结果，不得各自维护一套课程统计。

工作台的 `upcoming()` 一次聚合当前/相近学期的学期、课程、课表、作业、考试和 48 小时日程数据，并将已有结果传给对应 loader；只有全历史统计缺少时才额外读取全量成绩和选课数据。

### 7.4 学校通知

学校信息页使用两个公开接口，不依赖校园登录：

- 素质拓展：`https://sztz.zju.edu.cn/dekt/student/home/getTzggList?page=1&limit=30`
- 教务网：`xwck_cxMoreLoginNews.html?doType=query`

解析要求：

- 教务网使用登录页新闻接口；已登录管理端的 `xwgl_*` 接口可能返回 901，不应使用。
- 教务发布人字段使用 `xwfbr`，不要误读为 `fbr`。
- 素质拓展的 `fbsj` 按 UTC ISO 时间转换为北京时间。
- 摘要展示前通过 `stripHtmlText` 将 `<br>` 等换行转换为文本，并删除 HTML 标签；不得直接把 HTML 原文放进通知卡片。
- 各数据源可以独立缓存和回退；一个来源失败不能让另一个来源的通知消失。

### 7.5 校历与日程

- 公开 Celechron 校历 JSON 优先，失败时使用 `assets/calendars.json`。
- 公开校历当前请求地址是 `http://calendar.celechron.top/<semester>.json`，不是 HTTPS；Android 的 `network_security_config.xml` 只为这个域名显式允许明文请求，其他远程明文请求仍禁止。移动端/网络不可用时依赖仓库内置校历回退。
- `lib/domain/schedule.dart` 是 Flutter 当前节次和北京时间逻辑的唯一来源。
- 课程产品实际只有 1–13 节，当前课表视觉网格也只绘制 1–13 节。`sessionTimes` 中第 14、15 项是遗留的晚间时间数据，不代表存在第 14、15 节课；后续应清理或明确隔离。
- 工作台未来 48 小时日程和桌面挂件都使用同一套北京时间/校历投影逻辑。
- 旧 Web 使用 `archive/packages/core/src/domain/schedule.ts`，不要把 Flutter 的时间表改到旧包里，或在页面中重新抄一份时间。

### 7.6 预留服务

`ClassroomService` 和 `NetworkService` 的 stub 属于旧 Node 实现。Flutter 当前只有课堂占位页及校园网站外部链接，没有接入对应真实服务；不可伪造成功数据或在 Agent 中注册未实现的操作工具。

## 8. 文件下载、预览和备份规格

### 8.1 目录和命名

`application/files.dart` 负责本地文件生命周期：

- 默认使用应用支持目录下的 `downloads`，下载页支持自定义保存目录及恢复默认；设置页不再提供下载目录配置，只保留备份导入/导出。
- `FileService.setDownloadDirectory(String?)` 统一维护当前根目录和 `settings/app.downloadDirectory`，`AppServices.applyDownloadDirectory` 委托该方法并返回 `files.root`；启动从相同字段恢复。null、空白或默认路径恢复 `files.defaultRoot`，移除自定义字段并保留其他设置。
- `FileService` 不提供 `moveRoot`。`services.dart` 中读取旧 `settings/app.downloadDir` 并回退系统下载目录的 `downloadDirectory()` 是遗留辅助函数，不参与当前启动和切换流程。
- 按课程建立子目录，课程名和文件名都进行非法字符清理。
- 同名文件使用系统式的 `file (1).ext`、`file (2).ext` 递增命名。
- 文件名不包含下载记录 ID 或数据库 ID。
- Office 文件预览使用 PDF 预览版本（`officePdf=true`），不在页面上打开无意义的原始二进制。
- 所有目标路径必须经过 confined path 检查，防止 `..` 路径穿越；删除和打开前还要考虑符号链接/越界路径。

切换保存位置不会搬迁已有文件。下载记录保存 `relativePath` 和记录级 `downloadDir`，`FileService.file()` 依次查找记录目录、当前目录、默认目录。当前 `downloads_loader.dart` 的 `exists` 仍只检查当前根目录，可能把原目录内的文件标为已移除；这一页面状态与服务层查找的差异尚未统一。

### 8.2 并发和大文件

- 下载先写入临时 `.part` 文件，完成后再改名，避免半成品被当作完整文件打开。
- 使用流式响应、单块背压和最大 512 MB 文件限制，不能一次性把大文件读进内存。
- 同一目标路径的重复下载需要通过保留路径/任务状态避免竞争。
- 删除前先取消相关活动流；重新下载不应与旧流继续争抢文件或网络资源。
- 页面上的预览、打开、删除、重新下载和批量下载按钮必须拥有独立的 loading/error 状态，下载不能锁住整个页面。
- 批量下载复用单文件的取消、命名、错误和进度逻辑；批量任务失败时应保留已完成文件并报告每个失败项。

### 8.3 备份

`BackupService` 可以备份：

- conversations
- messages
- settings
- downloads
- audit

备份明确排除 secrets、cookies 和 pending confirmations。导入 zip 时必须校验归档路径穿越、单项大小和总大小，不能直接信任归档内的文件名。

## 9. Agent、模型和提示词

### 9.1 Agent 工具范围

当前 Flutter Agent 的工具包括：

- 课程、作业、课件、测验查询。
- 今日/未来 48 小时日程查询。
- 考试、课表、成绩和学校通知查询。
- 校园常识知识库搜索和文档读取。
- 单个/批量课程资料下载（普通挂件只读模式禁用下载）。

工具必须：

- 有明确的 schema 和参数校验。
- 标记 `read`、`write`、`external_download` 等风险等级。
- 对可能有外部影响、资源消耗或批量行为的操作进入确认流程。
- 不允许模型直接访问任意 URL。

普通会话和消息保存在本地数据库；桌面挂件使用 `mode: widget` 的一次性只读问答，不建会话、不写历史，也不能执行下载工具。Agent 最多运行 8 轮模型/工具迭代，待确认操作有效期为 5 分钟。

页面感知由 `domain/page_context.dart` 统一建模：路由页面、课程表学期、辅助栏学期、当前课程、课程详情 Tab 和页面摘要会实时同步到 `AppServices.currentPageContext`。`AgentService` 将上下文和当前页面推荐的 API/参数指引注入系统提示词，并提供只读工具 `zju_get_current_page_context` 供模型在多轮调用中获取最新状态。

### 9.2 模型来源

模型来源的业务结构包含：

```text
id
remarkName       # 用户可读备注名，不直接使用模型名代替
protocol         # openai / anthropic
baseUrl
model
apiKey           # 仅安全存储
enabled
```

上面 `remarkName` 是业务语义名称；Flutter 当前安全存储 JSON 为兼容既有数据使用键名 `name` 保存它，设置页通过“来源备注名”展示和编辑。不要把这个 `name` 误解成模型名。

设置页的视觉和语义要求：

- 第一行下拉框表示“当前来源”。
- 第二行下拉框表示“协议”。
- 两个字段必须有清楚的标签、间距和独立边界，不得重叠。
- 来源列表展示备注名；模型名只作为模型字段展示。
- “检测可用性”必须显示明确的成功/失败结果。
- OpenAI 兼容来源应从当前 base URL 的 `/models` 尝试读取可用模型，并检测当前模型，而不是只检查输入框是否非空。
- API key 为空时要区分保留已有 key 和没有可用 key 的情况。

请求拼接要求：

- base URL 没有版本段时才补 `/v1`。
- `.../v1`、`.../v4` 等已经包含版本段时直接拼接协议端点，不能生成 `.../v4/v1/chat/completions`。
- 清理末尾斜杠，正确处理本地 loopback HTTP 和 HTTPS。
- Anthropic 使用 Messages 协议和手动模型名，不假设存在 OpenAI `/models` 行为。

### 9.3 提示词资产

Flutter 当前提示词资产是 `assets/prompts.json`，不是旧 Node 服务的 Markdown/服务端提示词目录。加载流程必须：

1. 通过 `rootBundle.loadString(..., cache: false)` 读取资产。
2. 解析 JSON。
3. 校验 `SYSTEM_PROMPT_TPL`、`GUIDE_RULES`、`BRIEF_RULES` 必须存在且为有效文本。
4. 在错误阶段报告 `PROMPT_ASSET_MISSING`、`PROMPT_ASSET_INVALID` 或 `PROMPT_ASSET_INCOMPLETE`。
5. 组装昵称、人设、当前时间、数据摘要和知识库规则。

提示词资源加载失败时优先检查 `pubspec.yaml` 的 assets 声明、文件路径、构建产物和字段内容；不能用静默的空 fallback 掩盖打包问题。测试调用 `rootBundle` 时应先初始化 Flutter test binding。

### 9.4 校园知识库

Flutter 使用 `assets/knowledge.json`，它是从 CC98《浙江大学本科新生指引》（2026 版）整理的本地 JSON 资产。`application/knowledge.dart` 负责：

- 资产加载和内存缓存。
- 中文 2-gram + 英文词分词。
- IDF 加权检索。
- 安全的文档路径读取。

知识库全文不常驻模型上下文。系统提示词只注入目录/使用规则，回答前按需调用搜索工具。回答应标注参考《浙江大学本科新生指引》；政策类问题还应提醒以学校官方最新通知为准。检索不到时必须如实说明，不能用通用大学常识冒充浙大规定。

旧 Web 的知识库在 `archive/packages/server/knowledge/*.md`，由 `archive/packages/server/src/knowledge` 加载和检索。两种资产格式、路径和打包方式不同。

## 10. 页面与交互规格

### 10.1 全局布局

Flutter 使用 `CampusShell`：

- 宽度 >= 1024：桌面布局，左侧导航栏宽 240，主内容区可伸缩，宽屏页面显示辅助面板。
- 窄屏：顶部 AppBar、右上角设置/下载入口、主内容区和底部导航栏。
- 桌面主窗口默认 1320×900，最小 800×600。
- 页面不应依赖固定的超大宽度；卡片、表单、标题和按钮必须在 800px 窄桌面和手机宽度下没有 RenderFlex overflow。
- 功能页标题默认只显示主标题；只有学校信息页保留解释性副标题。

辅助面板规则：

- 课程页宽屏显示学期课程总览，窄屏通过页面入口/FAB 调出底部面板。
- 作业筛选已经并入主页面，不再强依赖右侧栏。
- 考试页移除不必要的右侧栏，学期切换直接放在主页面合适位置。
- 辅助面板被调出时不能阻塞主页面其他不相关操作。

### 10.2 工作台

工作台顺序：

1. 顶部日期、问候语、圆形头像和校园连接状态。
2. 接下来：未来 48 小时日程/作业切换。
3. 学业快览：本学期学业、待办作业、学业成绩、下载中心四张统计卡；考试数归入本学期学业卡。
4. 校园百宝箱：功能入口卡片矩阵。
5. 系统与连接状态。

统计卡要求：

- 四张卡当前统一为 136px 高度，保持一致的内边距和分隔线位置，最右侧下载管理卡不得单独变矮。
- 学业快览与课程总览辅助栏使用同一份 `loadCourseOverview` 聚合结果。第一张卡展示课程数、当前学期选课学分和考试数；成绩卡展示全量成绩计算的 GPA、获得学分和百分制加权均分；学在浙大课程列表不作为这些统计的独立数据源。
- 工作台加载时通过 `upcoming()` 共享相近学期课程、课表、作业、考试和 48 小时日程结果，避免各卡片和页面重复请求。
- 点击本学期课程数打开当前学期的课程总览弹层；点击成绩指标打开“全部学期”总览，点击考试数跳转考试页。
- 实际展示依赖仍包含刷新失败后回退的缓存时，显示“部分数据未能刷新，当前仍包含上次成功获取的数据。”；更新时间继续反映最早的真实依赖时间。
- 卡片默认背景保持纸张色。
- 悬停/选中表现为轻微浮起、阴影、边框和标题/数值/图标颜色变化，不要让整张卡片变成大面积金色或蓝色。
- 默认图标主色为蓝色，悬停时可以用金色强调。
- 卡片内部使用 `Expanded`、`Flexible` 或受约束的文本，长标题不能将箭头或操作挤出边界。
- 百宝箱卡片使用与 Web 参考实现相同的浮起/颜色/箭头动效，但初始颜色为蓝色，金色只作为交互态。

### 10.3 课程页

- 使用教务网课表数据按星期和节次展示课程。
- 7 个日期列在可用宽度内自适应；当前 `TimetableView` 的纵向实现仍是 `Stack`/`Positioned` 与固定 52px 节次高度，视觉网格只显示 1–13 节，课程文本在块内滚动。因此“纵向按内容自适应”仍是待改造项，当前不能宣称已经完全解决小屏课表需要滚动的问题；`sessionTimes` 的额外晚间项也不能视为第 14、15 节课。
- 课程内容区域允许滚动；网格线和课程块必须保持同一节次对齐。
- 课程块展示课程名、教师、地点和周次等信息；空间不足时使用合理截断或滚动，不让整页溢出。
- 宽屏右侧为学期课程总览；窄屏由辅助面板入口调出。
- 课程总览以教务网考签、全历史课表和全历史成绩为底座，按规范化学期/课程名去重并补充学分、教师和成绩；已建课状态及资料/作业仍从学在浙大关联。课表学期与辅助栏学期、刷新和更新时间互相独立。
- 课程数量、学分和成绩统计与右侧课程总览共用统一的教务网课程聚合；学在浙大课程列表只用于建课状态、课程资料、作业和测验关联。
- 统一使用无文字的刷新图标按钮；按钮位置在窄屏也不能破坏标题布局。

### 10.4 作业页

- 作业列表在主页面中展示，筛选/分类不再依赖固定右栏。
- 支持待办、临近截止、已截止等状态视图；当前临近截止阈值默认为 24 小时，并且只保存在作业页 widget 的内存状态中，没有从设置读取或持久化。若要让用户设置阈值，需要先确认设置项和保存范围。
- 每项显示课程、标题、截止时间、提交状态和附件摘要。
- 当前 Flutter 以查询和资料操作为主；未验收的作业提交按钮不可伪造为可用功能。
- 课程资料下载和打开操作使用独立状态，不因一个大文件下载而禁用整页其他操作。

### 10.5 考试页

- 按学期展示课程名、考试时间、地点和座位等字段。
- 默认当前/最近可用学期。
- 学期切换直接放在主页面，不保留无实际内容的右栏。
- 统一使用无文字的刷新图标按钮，避免窄屏标题与“刷新”文字互相挤压。

### 10.6 学校信息页

- 展示素质拓展和教务网通知，并标注来源、发布时间、发布人和摘要。
- 摘要必须为纯文本，HTML 标签和实体需要清理；保留 `<br>` 等合理换行。
- 信息页不使用下拉刷新；使用页面内刷新按钮。
- 通知标题可以保留必要的解释性文字，这是当前唯一保留副标题的功能页。

### 10.7 下载管理页

- 这是本地文件管理页，不应为了显示下载列表而等待无关校园网络请求。
- 资料按课程分组/文件夹存储。
- 支持预览、打开、删除和重新下载；批量下载当前只通过 Agent 的 `zju_batch_download` 工具提供，下载管理页没有多选后批量下载的独立 UI。
- 下载按钮、打开按钮、预览按钮必须处于真实可交互状态；弹窗不是必要的中间层。
- 大文件下载或删除期间，页面仍可以切换、查看其他文件和操作其他不冲突按钮。
- 出错时显示具体文件级错误，不能只显示全局“下载失败”。

### 10.8 设置页

设置分区包括：

- 统一身份认证：未认证时显示输入/认证；认证后保留状态和退出按钮，不把学号残留在输入框中。
- 模型来源：当前来源、协议、备注名、base URL、模型名、API key、模型列表和可用性检测。
- 个性化：圆形头像、昵称和默认人设/提示词。
- 下载目录配置已集中到下载管理页；设置页只保留本地备份导出/导入，不再重复提供目录选择、打开目录或恢复默认入口。
- 备份导出/导入。
- 清除本地数据和退出登录。

保存应用设置是整体覆盖操作：更新某一字段前必须展开已有设置，不能因为保存昵称或头像清除下载目录、模型来源等其他字段。

### 10.9 桌面挂件

- `platform/desktop.dart` 使用 `desktop_multi_window` 创建唯一的挂件子窗口，展示层级复刻旧 Web 挂件；日程通过主窗口转发的 `upcoming()` 获取，问答通过 `AgentService.chat(widget: true)` 获取，保持一次性只读且不写入普通聊天历史。
- 展开面板与 64×64 的“求是”小球是同一个 `WidgetApp` 的内部状态，不得为收起状态再创建一个窗口。展开/收起分别使用 380×560 与 64×64 的窗口尺寸并保持中心位置。
- 挂件使用透明背景、无标题栏/无边框、无阴影、置顶且不进入任务栏；日程点按和“打开应用”会唤起主窗口并跳转 `/` 工作台。
- `DesktopHost.initialize` 会扫描已有的 `widget:*` 子窗口，复用第一个并隐藏其余实例，避免热重载/热重启造成多个挂件。`windows/runner/flutter_window.cpp` 仅调整 secondary window 的 Win32 样式，主窗口保持普通边框。

### 10.10 AI 对话窗

- 通过独立 overlay 显示，不用全屏遮罩阻塞主界面。
- 桌面端可拖动标题栏移动；通过边框/角直接调整大小，不使用会遮住发送按钮的单独手柄。
- 有明确的最小宽高和窗口边界；调整大小时发送按钮、输入框和右下角边界不能重叠。
- Enter 发送；Ctrl/Meta+Enter 换行。
- 空白用户输入、空模型事件和空最终响应不得生成空消息卡片。
- 显示流式文本、工具步骤、错误和确认状态；聊天提示词资产失败时展示阶段化错误。
- 当前手机端把同一个 overlay 的宽高限制在 SafeArea 可用空间内，仍保留桌面端拖动/边框调整逻辑，还不是独立的底部面板；需要继续做真实触控验收，确认不会妨碍输入、发送和主界面操作。

### 10.11 个性化头像

- 设置页默认显示圆形默认头像。
- 点击圆形头像选择图片；图片在客户端压缩为适合本地设置的 data URL。
- 首页顶部问候语显示头像，聊天消息/聊天窗头像使用同一来源。
- 图片只保存在本机设置中，不上传到校园服务或模型服务。

## 11. 刷新、缓存与生命周期

### 11.1 首次进入刷新

`AppServices.claimInitialRefresh(pageKey)` 负责本次应用运行中的一次强制刷新：

- 用户第一次进入某个数据页面时绕过缓存、强制请求一次最新数据。
- 辅助栏/辅助面板应使用独立且稳定的 key，第一次真正打开时刷新一次。
- 同一页面再次进入不因为路由重建、手机通知栏展开/收起或普通生命周期变化而自动请求。
- 用户点击刷新或执行下拉刷新时强制请求最新数据。
- 退出登录时清除首次刷新记录，使下一次登录后的页面可以重新初始化。
- 学校信息页不使用下拉刷新，但标题栏刷新按钮会强制重新请求两个通知源；通知数据按一天缓存，并显示两路通知中最旧数据的更新时间。
- 下载管理页是本地文件管理例外，不参与页面首次进入刷新、网络数据缓存和“数据更新于 N 分钟前”提示。

### 11.2 缓存

- 课程、作业、资料、课表、考试、成绩和通知都应区分缓存数据、网络数据和错误状态。
- 默认缓存有效期为一天；本次运行第一次进入数据页、用户点击刷新或下拉刷新时都必须绕过缓存重新请求。不能在多个 widget 中各自实现一套缓存。
- 非认证网络失败可以显示过期缓存并标记 `stale`。
- 401/403/901 或明确的登录失效不能用旧数据伪装成“已连接”。
- 每条缓存记录至少要能提供数据更新时间和 stale 状态；页面展示最近一次成功数据距当前的分钟数。组合页面取实际展示依赖中最早的缓存时间，不能使用页面重组时间或无关历史缓存时间。通知的素质拓展、教务网两个来源必须独立缓存、独立刷新和独立回退。
- 通知结果保留 `updatedAt` 兼容字段，同时使用统一的 `_updatedAt` 参与页面时间聚合；两个通知来源的更新时间和失败状态始终独立维护。
- `CampusService` 按缓存 key 合并并发请求，成功写入缓存后通过 `cacheChanges` 广播资源变化。页面收到变化时按依赖从缓存重组，不能把广播再次转成强制网络请求；跨页面共享数据的内容和更新时间应实时同步。
- 首页连接状态读取凭据存在性和 `CampusSession.authStatus`，没有单独的状态探测请求；但工作台首次加载仍会调用课程/课表/作业/考试/48 小时日程加载器，实际是否联网由各数据缓存决定。`upcoming()` 会共享这些 loader 已取得的当前/相近学期结果，学业快览只在需要全历史统计时额外读取成绩和选课数据。模型卡片当前只表示存在来源配置，不等于实时可用性检测通过。

### 11.3 刷新完成与弹层同步

- `CampusPageState.refresh` 和 `CourseOverviewState.refreshOverview` 在刷新结束时同步更新状态，使刷新按钮恢复可用；页面释放后不再调用 `setState`。
- 辅助栏弹层使用独立路由，不能仅靠宿主页面的 `setState` 更新。`CourseOverviewState.overviewChanges` 通知数据 Future、学期和刷新状态变化，工作台与课程页的弹层通过 `ListenableBuilder` 订阅；通知器随页面释放。
- 缓存变更会通知已打开的弹层重建，内容和更新时间保持同步；课表学期与辅助栏学期仍然独立。
- 替换数据 Future 的 `setState` 回调必须使用同步语句块，避免赋值表达式把 Future 返回给 Flutter。
- 工作台 loader 按实际依赖的缓存 key 和校历资源计算 `_hasStaleData`。部分资源失败时保留上次成功时间并显示提示，不能把刷新请求结束时间写成数据成功时间。

## 12. 本地存储设计

### 12.1 Flutter 存储分层

| 数据 | 存储位置 | 说明 |
| --- | --- | --- |
| ZJU 账号密码 | `FlutterSecureStorage` | 不进入业务数据库 |
| 模型 API key | `FlutterSecureStorage` | 设置中只显示脱敏状态 |
| 校园 cookie | 内存 cookie jar | 退出/会话重置时清除 |
| 应用设置 | Drift/SQLite | 不包含 secret 本体 |
| 会话/消息 | Drift/SQLite | 本地 Agent 历史 |
| 缓存 | Drift/SQLite | 带时间和 stale 信息 |
| 下载记录 | Drift/SQLite | 文件状态和业务元数据 |
| 文件内容 | 本地 downloads 目录 | 按课程分目录 |
| 审计 | Drift/SQLite | 不写敏感原文 |

数据库由 `getApplicationSupportDirectory()` 下的 `agent.db` 提供，使用 Drift 的 `NativeDatabase.createInBackground`；测试可以使用 `AgentDatabase.memory()`。

### 12.2 业务集合

当前实现使用 Drift 记录集合/JSON 值的方式保存业务数据，逻辑集合至少包括：

- `settings`
- `conversations`
- `messages`
- `cache`
- `downloads`
- `audit`
- pending confirmations

新增持久化字段时应优先考虑：版本兼容、整体设置保存、导出/导入范围和敏感字段隔离，不要直接将临时网络响应永久化。

### 12.3 退出登录和清理

退出登录的目标行为必须：

- 取消 Agent 请求和活动下载。当前 `AppServices.logout()` 只调用了 `agent.cancelAll()`，尚未取消 `FileService` 中的进行中下载；这是实现缺口。
- 清除校园 session 和内存 cookie。
- 清除内存中的 secret/确认状态。
- 清除连接状态和相关缓存。
- 清除本次运行的首次刷新标记。

是否删除聊天历史和已下载文件，应由明确的用户操作决定，不能在普通退出登录中误删用户文件。

## 13. 安全要求

### 13.1 通用要求

- 密码、cookie、服务 ticket、API key 不得进入日志、异常堆栈、截图、审计原文或 Git。
- 错误信息对用户可读，但必须脱敏。
- 认证失败和服务不可用要有不同的状态，不能统一显示“已连接”或静默回退。
- 下载目录、备份导入和文件打开都要防止路径穿越。
- 高风险工具必须显示参数摘要、确认按钮和执行结果。
- 批量下载要显示范围和数量，不能由模型静默扩大范围。
- 用户可以清除凭据、会话、缓存和应用数据；清理动作要区分业务文件和密钥。

### 13.2 Flutter 特别要求

- 认证/模型 secret 只通过 `FlutterSecureStorage` 读写。
- 校园服务只访问允许的 HTTPS ZJU 子域名。
- 模型服务允许 HTTPS 和明确的本机 loopback HTTP，不允许任意不安全远程 HTTP。
- 不在 Flutter UI 中直接拼接未验证的外部 URL。
- 图片头像仅作为本地 data URL 保存，不发送到远端。

### 13.3 旧 Node 链路特别要求

- Fastify 只监听 `127.0.0.1`，默认端口 7788。
- `/api` 路由要求本地访问 token，health/bootstrap 是明确例外。
- Node 凭据使用旧实现的 AES-256-GCM 加密存储，不要把该格式误当成 Flutter 存储格式。
- `wrap(async () => ...)` 内返回原始数据，不要再次包 `ok(...)`，否则会产生双层信封。

## 14. 旧 Web/Electron/Node 维护说明

只有在用户明确要求维护旧 Web/桌面链路时，才使用本节的 API 和目录说明。

### 14.1 旧路由和包

- `archive/packages/server/src/server.ts` 统一注册旧 Fastify 路由。
- `/api/settings`：应用设置和模型来源。
- `/api/auth`：ZJU 凭据、验证和退出。
- `/api/zju`：学在浙大、教务网、通知等校园数据。
- `/api/files`：下载记录、预览和文件操作。
- `/api/agent`：聊天、SSE、确认和会话。
- `archive/apps/web/src/api` 使用 TanStack Query 调用这些路由。

### 14.2 旧 Web 仍需遵守的陷阱

- `wrap()` 双层信封：异步 handler 内只返回裸数据。
- 学在浙大文件下载端点使用上传 `id`，不是 `reference_id`。
- `joinUrl()` 只在 base URL 没有版本段时追加 `/v1`，智谱等 `/v4` 地址不能重复追加。
- 旧课表时间源是 `archive/packages/core/src/domain/schedule.ts`；不要把旧 Web 的时间逻辑复制到 Flutter。
- 旧知识库是 `archive/packages/server/knowledge/*.md`；不要把 Markdown 目录路径写入 Flutter 的资产加载逻辑。
- Electron 的原生 acrylic 在无边框、透明、置顶窗口上会出现灰板；这一实验结论只对 `archive/apps/desktop` 旧挂件有效，不适用于 Flutter 桌面宿主。

## 15. 迁移和开发路线

### 阶段 A：Flutter 主实现稳定化（当前）

- 保持认证、课程、作业、考试、通知、下载、Agent 和设置主路径可用。
- 完成 Windows 真实账号登录、SQLite、安全存储和大文件下载验收。
- 对齐旧 Web 的视觉层级和关键交互，但以 Flutter 的响应式实现为准。
- 解决窄屏 RenderFlex overflow、右栏/辅助面板、可拖动聊天窗和卡片交互回归。
- 保持首页连接状态、课程统计、提示词资产和模型检测的真实反馈。
- 2026-09-11 全量扫描已确认的代码缺口：课程资料加载失败时当前 `FutureBuilder` 先判断 `!hasData`，会把错误态遮成持续 loading；工作台和课程资料弹层仍有 `Text('${snapshot.error}')`，需要改为脱敏的阶段化错误；退出登录尚未取消 `FileService` 的活动下载。
- 2026-09-12 已完成页面感知上下文、首页与课程总览统一聚合、工作台共享加载、缓存 key 请求去重、跨页面缓存广播和依赖更新时间聚合；后续修改必须保持这些共享边界，不要在页面中重新发明独立请求或时间戳。
- 2026-09-12 完成七个页面、功能组件、页面 loader 与领域规则拆分，移除旧集中页面和兼容导出入口。新增生命周期回归；该阶段 `flutter test --no-pub` 共 105 项通过，`flutter analyze --no-pub` 输出 `No issues found!`。
- 随后修复课表附加元数据解析、刷新结束状态、已打开辅助弹层的状态同步，并增加工作台部分刷新失败提示。当时按用户要求未再运行测试或分析；2026-09-13 已对当前代码执行全量普通测试和静态检查，手工验收仍需独立完成。
- 2026-09-13 修复合并后下载目录切换仍调用不存在的 `moveRoot` 的编译问题，改为复用 `FileService.setDownloadDirectory`；通过 `flutter pub get` 恢复 `pointycastle` 的本机包解析配置。全量 126 项普通测试和静态检查通过；原生集成测试因 Debug EXE 占用而未完成，用户随后确认运行时问题已解决。
- 2026-09-13 根据旧 Web 挂件复刻 Flutter 挂件展示层，保留现有 `upcoming()` 与只读 Agent 数据链路；展开面板和 64×64 小球统一为同一个透明无边框子窗口，日程点按跳转工作台，启动时复用已有挂件并隐藏重复实例。设置页移除重复的下载目录配置，只保留下载页作为目录配置入口，并同步移除设置页上下文中的该描述。
- 2026-09-13 为 `desktop_multi_window` secondary window 增加 Win32 无边框处理；同时将 `flutter_window.cpp` 注释保持为当前代码页可表示的 ASCII，解决 MSVC C4819/C2220。Windows 构建随后由用户确认成功，本轮未重复构建。
- 七个功能页已有 1320/800/390px 的渲染回归，覆盖路由切换、筛选状态、首次/手动刷新、缓存广播和本地下载页；设置、聊天窗、多宽度 golden 及真机触控仍未完整覆盖。
- 同一轮扫描还确认：`assets/prompts.json` 已声明并由普通测试覆盖，运行时若仍提示加载失败应排查构建产物的资源路径/缓存；校历的 `http://calendar.celechron.top` 是 Android 唯一明文例外且有内置回退；Android release 目前使用 debug signing config，正式发布前必须补正式签名。真实登录链路已由用户实测，不再作为本轮待验证项。

### 阶段 B：Android 和跨平台验收

- 验证 Flutter secure storage、SQLite、文件选择、content URI 和文件打开。
- 验证窄屏底部导航、辅助面板、聊天输入和下拉/手动刷新行为。
- 验证不依赖 Windows 窗口 API 的业务层和 Agent 层。

### 阶段 C：明确范围后扩展

- 如用户确认，再实现作业提交。
- 如获得稳定接口，再实现智云课堂资源。
- 如获得明确支付/充值方案和授权，再实现校网状态及充值流程；充值必须独立确认且不能由 Agent 静默执行。
- 如要继续维护旧 Web，应单独记录旧链路变更，不要把两套实现混成一套迁移目标。

## 16. 测试与验收计划

### 16.1 Flutter 自动测试

在项目根目录执行：

```powershell
flutter test
flutter analyze
```

测试应覆盖：

- 领域模型、课表合并、节次时间和课程数量去重。
- 学期映射、北京时间和校历投影。
- 登录 cookie、重定向和认证状态判断。
- LLM base URL、版本段、OpenAI/Anthropic 请求和模型列表。
- 提示词资产缺失、无效 JSON 和字段不完整。
- HTML 摘要清理和通知日期/发布人解析。
- 文件名清理、重复命名、路径隔离、删除和备份归档安全。
- `test/storage_test.dart`：应用服务切换下载目录、创建目录、持久化与保留其他设置、恢复默认，以及切换后按下载记录查找原目录文件。
- `test/webvpn_test.dart`：WebVPN 链接、端口/路径/查询串保留与单块/多块 AES 加密。
- 空聊天输入/空响应过滤、Agent 工具 schema 和确认状态。
- 页面上下文序列化、页面切换/学期/课程详情同步、`zju_get_current_page_context` 工具。
- 学业快览与课程总览统一数据源、课程统计、缓存请求去重、`cacheChanges` 跨页面通知和更新时间依赖聚合。
- `test/feature_page_lifecycle_test.dart`：入口 key 不变时的路由切换、作业分类参数、首次/手动刷新、缓存广播、本地下载页和七个功能页在 1320/800/390px 下的渲染。
- 依赖兼容性和 Drift 内存数据库。

最近一次全量通过记录为 2026-09-13：`flutter pub get` 成功，`flutter test --no-pub` 全量 126 项通过，`flutter analyze --no-pub` 输出 `No issues found!`，三者退出码均为 0。这是当前代码的普通测试与静态检查结果，不替代真实校园接口和全量手工验收。

原生 Windows 测试：

```powershell
flutter test integration_test/native_storage_test.dart -d windows
```

2026-09-13 使用 `--no-pub` 尝试执行该原生测试时，链接器因运行中的 Debug 客户端占用 `zju_campus_agent.exe` 报 `LNK1168`，测试未完成，不能记为原生存储验收通过。用户随后确认运行时问题已解决，与自动原生测试结果分别记录。

真实登录测试必须显式开启：

```powershell
flutter test integration_test/native_login_test.dart -d windows --dart-define=VERIFY_SAVED_CAMPUS_LOGIN=true
```

### 16.2 Flutter 手动验收清单

#### 认证和首页

- 未认证时设置页显示可操作的认证入口。
- 认证成功后显示连接状态和退出按钮，输入框不残留学号。
- 认证失效/forbidden 后首页状态不会继续显示已连接。
- 反复进入首页不会每次强制请求校园接口。
- 每个数据页面本次运行首次进入时强制刷新一次，之后手动刷新仍强制请求最新数据；相同缓存 key 的并发请求只产生一次网络请求；页面标题显示实际依赖数据中最早的“数据更新于 N 分钟前”。
- 手动刷新成功后内容与真实缓存时间同步，按钮结束刷新状态；某个依赖失败时保留旧时间，工作台显示部分刷新失败提示。

#### 数据和页面

- 首页学业快览与课程总览辅助栏的课程数、学分、成绩和绩点来自同一份教务网课程聚合结果；学在浙大只负责课程关联及资料/作业数据。
- 课程表在宽屏、800px 窄桌面和手机宽度下完整可读（当前 52px 固定节次高度和仅绘制 1–13 节仍是未完成项）。
- 窄屏课程页可以通过辅助面板入口查看课程总览。
- 保持课程总览弹层打开时刷新或收到其他页面的缓存更新，内容、更新时间及按钮状态同步变化；切换辅助栏学期不改变课表学期。
- 作业筛选在主页面可用，考试页不出现空右栏。
- 通知摘要不显示 HTML 标签。
- 课程表、考试和工作台使用无文字刷新图标按钮，标题不换行溢出。

#### 卡片和响应式

- 四张学业快览卡高度一致，下载管理卡不单独变矮。
- 卡片悬停/选中是浮起、阴影和文字/图标变化，不是整张卡大面积变色。
- 百宝箱卡默认蓝色，悬停才金色高亮。
- 长标题和操作箭头不产生 RenderFlex overflow。
- 手机端设置/下载入口位于右上角，辅助面板可通过按钮调出。

#### AI 和模型

- 对话窗可移动、可拖动边框调整大小，手柄不遮住发送按钮。
- Enter 发送，Ctrl/Meta+Enter 换行。
- 空响应不生成重复空卡片。
- 提示词资产错误能显示实际阶段和资源原因。
- 模型来源字段不重叠，备注名和模型名语义分离。
- 可用性检测显示结果，OpenAI 兼容 base URL 能读取 `/models` 并检测当前模型。

#### 下载和文件

- 资料列表可直接预览、打开、删除和重新下载。
- 文件按课程进入不同文件夹，同名文件自动追加 `(1)`，不出现记录 ID。
- 下载页更改目录后写入统一配置，重启后恢复选择；设置页不再提供目录配置入口。恢复默认保留昵称等其他设置，已有文件不会被搬迁或删除。目录切换后旧文件的列表状态与实际查找结果仍需核对。
- 大文件下载期间仍可操作页面其他内容。
- 下载过程中重新下载或删除不会卡死或永久占用按钮。
- 批量下载显示进度和单项错误，完成项不因其他项失败而丢失。

#### 桌面和手机

- Windows 主窗口和桌面挂件都能启动，托盘操作正常。
- 挂件不出现系统白色边框或阴影；展开面板和 64×64 小球在同一个窗口内切换，收起后不改变为全屏/半屏窗口。
- 点击挂件日程或“打开应用”会唤起主窗口并进入工作台；挂件问答仍为只读一次性问答。
- 挂件只使用只读一次性问答，不污染普通聊天历史。
- 手机上底部导航、页面滚动、输入法和辅助面板都可用。

### 16.3 旧 Web/Node 测试

旧链路修改后执行：

```powershell
cd archive
pnpm typecheck
pnpm lint
pnpm test
```

涉及真实 ZJU 账号时仍需手工端到端验收，并检查 Node 数据目录的 `audit_logs` 不含密码、cookie、ticket 或 API key。

## 17. 错误处理约定

Flutter 和旧 Node 可以使用不同的错误承载方式，但错误语义应保持清楚：

```text
CONFIG_MISSING
MODEL_PROVIDER_INVALID
MODEL_AUTH_FAILED
MODEL_UNAVAILABLE
MODEL_LIST_FAILED
PROMPT_ASSET_MISSING
PROMPT_ASSET_INVALID
PROMPT_ASSET_INCOMPLETE
ZJU_CREDENTIAL_MISSING
ZJU_AUTH_FAILED
ZJU_SESSION_EXPIRED
ZJU_SERVICE_LOGIN_FAILED
ZJU_SERVICE_UNAVAILABLE
ZJU_RESPONSE_PARSE_FAILED
TOOL_INPUT_INVALID
TOOL_CONFIRMATION_REQUIRED
TOOL_CONFIRMATION_REJECTED
FILE_NOT_FOUND
FILE_PATH_INVALID
FILE_DOWNLOAD_FAILED
FILE_DOWNLOAD_CANCELLED
FILE_DELETE_FAILED
BACKUP_INVALID
NETWORK_RECHARGE_FAILED       # 预留，不代表当前已实现
UNKNOWN_ERROR
```

用户提示至少应包含：发生在哪个阶段、是否可以重试、是否需要重新认证、是否已经产生部分文件/操作。不要只显示一个没有上下文的“加载失败”。

## 18. 给后续实现模型的注意事项

1. 先判断任务属于当前 Flutter 实现还是旧 Web/Electron/Node 实现；默认处理 Flutter。
2. 用户说“参考 Web”通常表示对齐旧 Web 的视觉/交互，不表示修改 `archive/apps/web`。
3. 不要把 `login-zju` 引入 Flutter 或浏览器，不要复制上游登录源码。
4. 不要把密码、cookie、ticket、API key 写日志或提交；错误和审计只记录脱敏摘要。
5. 所有异步工作完成后再同步更新 Flutter widget 状态，不要把 `async` 闭包传给 `setState`。
6. 修改响应式布局时检查宽屏、800px 窄桌面和手机宽度；优先使用 `Expanded`、`Flexible`、`Wrap`、滚动容器或受约束文本，不要靠任意增高掩盖 overflow。
7. 资源改动同步检查 Flutter `pubspec.yaml`；提示词资产问题应排查打包路径和字段，不要用空 fallback。
8. 课表课程数必须使用教务网去重结果；课件/作业等仍按各自服务的数据源处理。
9. 文件下载始终使用上传 `id`，按课程分目录，同名自动追加序号，不能使用数据库记录 ID 命名。
10. 大文件操作必须可取消、流式、临时文件落盘，不能锁住整个页面或与删除/重新下载竞争同一资源。
11. 新增纯函数时增加对应测试；修改认证、模型 URL、文件路径和提示词资源时必须增加回归覆盖。
12. 不要执行 `git reset --hard`、覆盖用户未提交修改或其他破坏性操作，除非用户明确要求。
13. 修改 `archive/start-dev.bat` / `archive/stop-dev.bat` 时保持 GBK + CRLF；不要直接用普通 UTF-8 编辑器保存。
14. `archive/packages/core` 的课表时间和 Flutter `domain/schedule.dart` 是两套实现，修改前先确认目标运行时。
15. 页面按 `ui/pages/`、功能组件、`application/page_loaders/` 和 `domain/` 分层维护；不重建集中页面文件或兼容导出入口。更新时间来自实际缓存依赖，弹层必须订阅状态变化，不能用当前时间掩盖刷新失败。

## 19. 默认假设

如无额外说明，按以下假设处理：

- 部署形态：本地优先。
- 当前 UI 和业务实现：Flutter，目标先覆盖 Windows，再完成 Android 验收。
- 旧 Web/Electron/Node：只在明确要求时维护。
- 模型协议：OpenAI 兼容或 Anthropic；API key 只进系统安全存储。
- 校园认证：ZJUAM/CAS，学在浙大和教务网分服务内存 cookie。
- 教务网负责课表、考试、成绩及首页课程数量；学在浙大负责课程资料、作业和测验。
- 查询工具可以直接执行；下载、批量或可能有外部影响的操作需要可见确认。
- 学校通知是公开接口，但仍需清理 HTML、处理来源和缓存错误。
- 桌面端使用左侧导航和可见辅助面板，窄屏使用顶部操作入口、底部导航和可调出的辅助面板。
- 卡片默认纸张色/蓝色图标，交互态使用浮起、阴影、边框和颜色变化。
- 任何未在“当前已完成路径”中列出的服务或操作，都应先确认范围再实现。
