# 求是书院 · 浙江大学校园智能助手

本地优先的浙江大学校园智能助手。当前主实现是 Flutter 客户端：校园认证、校园数据请求、模型请求和本地数据都在客户端完成，不依赖 Node 或本地业务 HTTP 服务。

仓库中仍保留一套旧的 React/Electron/Node 实现，用于维护历史 Web 版本和对照界面。当前 Flutter 开发、界面调整和功能验收默认只修改 `apps/flutter`；除非明确提出 Web 需求，不要修改 `apps/web`。

> 项目约定和更完整的代码导航见 [`AGENTS.md`](AGENTS.md)，产品规格见 [`ZJU_CAMPUS_AGENT_PROJECT.md`](ZJU_CAMPUS_AGENT_PROJECT.md)。

## 当前状态

- Flutter Windows 客户端已覆盖认证、课程、课表、作业、考试、通知、成绩、资料下载、本地 AI 对话、模型设置、个性化和桌面挂件的主要路径；页面感知上下文也已接入 Agent 和聊天。
- 当前正在进行迁移后的界面/交互对齐，以及 Windows 和手机端的响应式验收。
- Windows 已能原生编译；Android 和全量功能验收尚未完成。
- 智云课堂目前是占位页，百宝箱提供校园网站的外部链接；校网充值和作业提交尚未作为已完成能力提供。旧 Node 中的服务 stub 不代表 Flutter 已接入对应接口。
- 应用不提供云端部署，数据默认保存在本机。

2026-09-12 当前边界：部分错误态仍需改为阶段化展示，退出登录尚未统一取消活动下载；提示词资源已通过普通测试，运行时异常应排查资源打包路径。七个功能页已增加 1320/800/390px 的渲染回归，设置、聊天窗和触控交互仍需继续验收；Android release 仍需正式签名。

## Flutter 客户端

### 主要功能

- 使用浙江大学统一身份认证访问学在浙大和教务网。
- 从教务网读取课表、考试、成绩和全历史选课信息；首页学业快览与课程总览共用教务网课程聚合结果，统一计算课程数、学分、成绩和绩点。
- 从学在浙大读取课程、课件、作业和测验，并负责课程建课状态及资料/作业关联，不作为首页学业统计的课程底座。
- 展示素质拓展平台与教务网通知，并在摘要展示前去除 HTML 标签。
- 资料按课程分类保存到本地文件夹，支持预览、打开、删除和重新下载；下载页和设置页支持更改保存目录、恢复默认，默认目录为应用支持目录下的 `downloads`。切换目录不搬迁已有文件；批量下载当前通过 Agent 工具提供，下载页暂没有多选批量操作；大文件使用流式传输。
- 支持 OpenAI 兼容协议和 Anthropic 模型来源，可从 OpenAI 兼容 base URL 读取模型列表并检测当前模型可用性。
- 本地 Agent 支持校园数据查询、知识库检索和需要确认的操作；普通聊天会话保存于本机，桌面挂件使用只读的一次性问答。Agent 会接收当前页面、学期、辅助栏和课程详情上下文，也可主动读取实时页面上下文。
- 内置《浙江大学本科新生指引》知识库，按需检索相关段落，不把全文常驻放入提示词。
- Windows 桌面挂件显示未来 48 小时日程和待办，并提供系统托盘入口。

### 环境要求

- Flutter >= 3.44
- Dart >= 3.12
- Windows 构建需要 Visual Studio 的 C++ 桌面开发工作负载和 Windows SDK。
- 依赖版本由 `apps/flutter/pubspec.lock` 固定，该文件应随项目提交。

### 运行和检查

在 `apps/flutter` 目录执行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

构建 Windows 发布包：

```powershell
flutter build windows --release
```

发布时需要携带完整的 `build/windows/x64/runner/Release` 目录，包括 DLL 和 `data` 目录，不能只复制 exe。

原生 SQLite/安全存储检查：

```powershell
flutter test integration_test/native_storage_test.dart -d windows
```

依赖兼容性测试位于 `apps/flutter/test/dependency_compatibility_test.dart`。

合并代码后先执行 `flutter pub get`。若出现 `pointycastle` 无法解析，通常是本机包解析配置未同步；该依赖已在声明和锁文件中。服务字段变更后若热重载出现 `FileService._root` 空值异常，在 `flutter run` 终端按大写 `R` 执行 Hot Restart，或停止后重新启动。Windows 构建遇到 `LNK1168` 时检查同一路径的客户端是否仍在运行。详细说明见 [Flutter 开发排错](apps/flutter/README.md#开发排错)。

### 真实登录检查

登录凭据只在应用设置中填写，并通过系统安全存储保存。CAS、学在浙大和教务网分别维护内存 cookie；应用不会把密码、cookie、ticket 或模型 API key 写入日志。

只检查公开登录页和公钥，不提交凭据：

```powershell
cd apps/flutter
flutter test tool/check_login_transport.dart
```

完整真实登录检查默认不运行。先在应用中保存真实凭据，再显式执行：

```powershell
cd apps/flutter
flutter test integration_test/native_login_test.dart -d windows --dart-define=VERIFY_SAVED_CAMPUS_LOGIN=true
```

该测试用于手工验收，不属于普通自动回归，避免反复向学校服务提交登录请求。

### 响应式界面

- 桌面布局在宽度 >= 1024 时使用侧边导航和宽屏辅助面板。
- 窄屏使用顶部操作入口和底部导航；设置、下载等入口会移动到右上角。
- 课程表界面（宽屏与窄屏）表头直接集成 Tab 切换学期胶囊与操作区（导出图片、导出 Excel、刷新课表）；窄屏下自动自适应为紧凑图标按钮；课表与学期总览辅助栏学期解耦、刷新独立。辅助栏课程详情弹层提供“作业”Tab 展示该课程作业。
- 待办作业展示当前及相近学期作业，未截止及逾期 1 周内的作业有序展示并优先提示未完成项。
- 设置页中的大模型配置和个性化设置卡片支持平滑折叠展开，默认收起以保持紧凑。
- 课程页窄屏通过入口调出辅助面板，作业筛选并入主内容，考试页不保留冗余右栏。
- AI 对话窗在桌面端可以拖动标题栏并拖动边框调整大小；手机端当前把同一个 overlay 限制在 SafeArea 可用空间内，底部面板和触控尺寸验收仍待完成。
- 每个数据页在本次运行第一次进入时强制请求一次最新数据；之后用户点击刷新或下拉刷新时仍强制绕过缓存。数据缓存默认一天有效，页面标题显示“数据更新于 N 分钟前”；学校信息页不使用下拉刷新，但保留刷新按钮。相同缓存 key 的并发请求会合并，缓存成功写入后会通知其他页面从缓存重组数据。

### 刷新与缓存机制

- `AppServices.claimInitialRefresh(pageKey)` 记录本次应用运行中已经首次进入过的页面。每个数据页（包括首次打开的辅助面板）第一次进入时必须绕过缓存并请求最新数据。
- 页面再次进入、路由重建、手机通知栏展开/收起或普通生命周期变化，不得因此自动重复请求。
- 用户点击刷新或执行下拉刷新时始终强制请求最新数据，不使用仍在有效期内的缓存。
- 课程、课表、作业、考试、成绩、通知和校历缓存默认有效一天；网络失败时可以展示过期缓存并标记为旧数据，同时保留错误状态。
- 通知页也使用同一套缓存机制；它不使用下拉刷新，但页面刷新按钮仍然强制刷新两个通知来源。
- 数据页面显示实际依赖数据中最早一次成功缓存的更新时间，格式为“数据更新于 N 分钟前”；跨页面收到缓存变更后只做本地重组，不把通知转成重复网络请求。下载页是本地文件管理页，不参与这套网络数据缓存和更新时间提示。
- 刷新结束后更新按钮状态；已打开的课程总览弹层同步接收刷新和缓存变化，更新内容、学期及时间。工作台仍包含刷新失败后回退的数据时，会显示“部分数据未能刷新，当前仍包含上次成功获取的数据。”，并保留真实的旧数据时间。
- 退出登录时清除首次进入记录和相关缓存，下一次登录后各页面可以重新初始化。

### 数据加载与页面联动

- 工作台通过一次 `upcoming()` 共享当前/相近学期的课程、课表、作业、考试和 48 小时日程数据；学业快览需要全历史统计时才额外读取全量成绩和选课数据。
- 课程表学期和课程总览辅助栏学期彼此独立，刷新也彼此独立；辅助栏统计和更新时间只依赖它实际展示的缓存资源。
- 页面上下文由 `apps/flutter/lib/domain/page_context.dart` 统一建模，路由、学期、辅助栏、课程详情和详情 Tab 变化会实时同步给 `AppServices` 和 Agent。

### 页面与业务模块

工作台、课程表、作业、考试、学校信息、下载和课堂占位页已拆成七个独立页面，各自管理筛选条件、加载和页面上下文。原集中页面实现与兼容导出入口均已删除，应用和测试直接引用所属模块。

| 目录或文件（相对 `apps/flutter/lib`） | 职责 |
| --- | --- |
| `ui/pages/` | 独立页面；`feature_page.dart` 只负责路由适配 |
| `ui/shared/` | 通用布局、加载、刷新、缓存订阅和文件动作 |
| `ui/courses/`、`ui/assignments/`、`ui/exams/`、`ui/downloads/`、`ui/dashboard/` | 各功能组件和交互状态 |
| `application/page_loaders/` | 页面数据组合、缓存依赖和更新时间聚合 |
| `application/course_overview.dart`、`application/course_details.dart` | 课程总览聚合、课程匹配和元信息补全 |
| `domain/` | 课程规范化、成绩计算、作业规则、小学期筛选等纯业务逻辑 |

新增页面沿用这些边界，业务模块不依赖 UI。具体页面入口见 [Flutter 页面模块导航](apps/flutter/lib/ui/pages/README.md)。

## 数据与安全

Flutter 客户端的主要代码位于 `apps/flutter/lib`：

```text
lib/
├── application/       # 校园服务、文件、Agent、模型和应用服务容器
├── data/              # Drift 数据库、凭据和内存 cookie session
├── domain/            # 课表、时间、领域模型和纯函数
├── platform/          # Windows 桌面宿主、文件保存等平台能力
└── ui/                # 页面、主题、头像、导出和悬浮聊天窗
```

- Drift SQLite 数据库位于 Flutter 的 `getApplicationSupportDirectory()` 下。
- 浙大凭据与模型 API key 使用 `FlutterSecureStorage`，不保存在普通业务数据库。
- 校园 cookie 只保存在内存中的分服务 cookie jar。
- 网络数据缓存默认有效一天；网络失败时可以展示过期缓存并标记为旧数据，认证失效不能伪装成正常连接。
- 备份包含会话、消息、设置、下载和审计记录，不包含 secrets、cookies 和待确认操作。

## 依赖说明

2026-09-11 的 Flutter 依赖维护包括：

- `go_router` 18.0.1
- `file_picker` 12.2.0
- `flutter_secure_storage` 11.1.0
- `drift` 当前由 `pubspec.yaml` 的 `^2.30.0` 约束，锁文件解析为 2.35.0
- `flutter_markdown_plus` 1.0.12

`archive` 3.6.1 和 `xml` 6.6.1 暂时保留，因为 `excel 4.0.6` 对它们有版本约束；`material_color_utilities` 和 `test_api` 的旧版本由当前 Flutter SDK 固定。不要用 `dependency_overrides` 强行跨越这些约束。Android release 当前仍使用 debug signing config，正式发布前需要补正式签名。

最近验证记录（2026-09-13）：已修复下载目录切换对旧 `moveRoot` 接口的调用，并通过 `flutter pub get` 恢复 `pointycastle` 的本机解析配置。`flutter test --no-pub` 全量 126 项通过，`flutter analyze --no-pub` 输出 `No issues found!`，退出码均为 0。Windows 原生存储集成测试因运行中的 Debug 客户端占用 EXE（`LNK1168`）未完成；用户随后确认运行时问题已解决。更多细节见 [`apps/flutter/README.md`](apps/flutter/README.md)。

## 旧 Web/Electron/Node 实现

旧实现仍可独立运行，但不代表当前 Flutter 客户端的架构：

```text
React UI (apps/web)
  │ /api + 本地访问 token
  ▼
Fastify (packages/server, 127.0.0.1:7788)
  ├── packages/llm            OpenAI / Anthropic 适配器
  ├── packages/zju-services   login-zju 校园服务适配器
  ├── SQLite                  会话、缓存、下载和审计
  └── 加密凭据                旧 Node 链路的凭据存储
```

旧实现的开发命令在仓库根目录执行：

```powershell
pnpm install
pnpm dev:server
pnpm dev:web
```

也可以在 Windows 上双击 `start-dev.bat`，由 `scripts/dev-launcher.mjs` 后台托管旧的 Fastify/Vite/Electron 托盘和桌面挂件；使用 `stop-dev.bat` 停止。

旧实现的代码和资源包括：

- `apps/web`：React 18 + Vite 前端。
- `apps/desktop`：Electron 壳、托盘和旧桌面挂件。
- `packages/server`：旧 Fastify API、SSE Agent、缓存和加密凭据。
- `packages/zju-services`：服务端 `login-zju` 封装。
- `packages/server/knowledge`：旧 Web/Node 侧的 Markdown 知识库；Flutter 使用的是 `apps/flutter/assets/knowledge.json`，两者不要混用。

旧实现的本地 API 只绑定 `127.0.0.1`。`login-zju` 仅允许在旧 Node 服务端使用，不能引入 Flutter 或 `apps/web`。

## 测试与开发约定

Flutter 修改后优先执行：

```powershell
cd apps/flutter
flutter test
flutter analyze
```

旧 Web/Node 修改后执行：

```powershell
pnpm typecheck
pnpm lint
pnpm test
```

开发时特别注意：

- 所有异步工作完成后再同步更新 widget 状态，不要把 `async` 闭包传给 `setState`。
- 窄屏布局使用 `Expanded`、`Flexible`、`Wrap` 或滚动容器解决内容约束，不要用任意增大高度掩盖 RenderFlex overflow。
- 提示词资产 `apps/flutter/assets/prompts.json` 缺失或字段不完整时，应修复资源声明/打包路径，不要用空 fallback 掩盖问题。
- 课程数量、考试数量等统计要明确数据源，不能把学在浙大课程列表和教务网课表混为一谈。
- 文件下载使用学在浙大的上传 `id`，不要误用 `reference_id`；同名文件使用 `file (1).ext` 形式处理，不要把数据库记录 ID 放进文件名。
- 不要执行 `git reset --hard`、覆盖未提交修改等破坏性操作，除非用户明确要求。

## 相关文档

- [`AGENTS.md`](AGENTS.md)：当前项目导航、架构差异和编码约定。
- [`apps/flutter/README.md`](apps/flutter/README.md)：Flutter 依赖、平台构建和登录验证细节。
- [Flutter 页面模块导航](apps/flutter/lib/ui/pages/README.md)：独立页面入口、公共组件和业务分层。
- [`ZJU_CAMPUS_AGENT_PROJECT.md`](ZJU_CAMPUS_AGENT_PROJECT.md)：产品规格和阶段规划。
- [`docs/`](docs/)：设计对比、代码审查和其他开发记录。
