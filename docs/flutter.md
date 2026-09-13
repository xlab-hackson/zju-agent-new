# 求是助手 · Flutter 客户端

校园认证、校园接口、模型请求与本地数据库均在客户端运行，不需要 Node 或本地业务 HTTP 服务。当前仍在迁移和验收阶段；Windows 已能原生编译，Android 及全量功能验收尚未完成。旧数据导入已按需求取消。

## 运行与检查

要求 Flutter >=3.44、Dart >=3.12（与 go_router 18 的最低要求一致）。依赖版本由 `pubspec.lock` 固定，请提交锁文件以保持 Windows 和 Android 构建一致。

将符合版本要求的 Flutter 加入 PATH 后，在仓库根目录执行：

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter build windows --release
flutter test integration_test/native_storage_test.dart -d windows
```

Windows 发布时需要携带整个 `build/windows/x64/runner/Release` 目录，包括 DLL 和 data，不能只复制 exe。编译需要 Visual Studio C++ 桌面开发工作负载和 Windows SDK。

## 依赖维护

2026-09-11 升级：`go_router` 18.0.1、`file_picker` 12.2.0、`flutter_secure_storage` 11.1.0，以及可兼容的间接依赖；`drift` 的 `pubspec.yaml` 约束仍为 `^2.30.0`，当前锁文件解析为 2.35.0。Markdown 切换到维护中的 `flutter_markdown_plus` 1.0.12，移除未使用的 `cookie_jar`。

- 文件选择使用 `pickFile()` / `readAsBytes()`；`saveFile()` 在各平台自行保存并返回 URI，应用不再重复写文件。参见 [file_picker 12 变更](https://pub.dev/packages/file_picker/changelog)。
- 安全存储升级不使用 v10 已废弃的加密配置。Android 最低 API 24，由当前 Flutter 的 `minSdkVersion` 提供；Windows 使用 DPAPI。参见 [安全存储变更](https://pub.dev/packages/flutter_secure_storage/changelog)。
- `archive` 3.6.1、`xml` 6.6.1 暂保留：Excel 4.0.6 对它们分别约束为 `^3.6.1` 和 `<7.0.0`。升级需另行迁移 Excel 库，不能通过 `dependency_overrides` 强行跨版本。
- `material_color_utilities` 0.13.0 与 `test_api` 0.7.12 由当前 Flutter SDK 固定，随 SDK 更新处理。`flutter pub outdated` 仍显示这四项属于预期。
- `pointycastle` 4.0.0 已声明并锁定，供 `domain/webvpn.dart` 构造 WebVPN 链接时进行 AES 加密。2026-09-13 的包解析修复只执行了 `flutter pub get`，未更改依赖版本或锁文件。

依赖兼容测试在 `test/dependency_compatibility_test.dart`，覆盖 Markdown 表格及链接导航、保存取消与 Android content URI；原生安全存储和 SQLite 测试见 `integration_test/native_storage_test.dart`。

最近验证记录（2026-09-13）：`flutter pub get` 成功，`flutter test --no-pub` 全量 126 项通过，`flutter analyze --no-pub` 输出 `No issues found!`，三者退出码均为 0。覆盖 WebVPN 链接与 AES、设置页/下载页以及新增的 `AppServices` 下载目录切换、恢复默认、其他设置保留和原目录文件查找回归。随后 `flutter_window.cpp` 的 MSVC C4819/C2220 编译问题已修复，Windows 构建由用户确认成功；本轮未重复构建。

本次 `flutter test integration_test/native_storage_test.dart -d windows --no-pub` 在链接阶段因运行中的 Debug 客户端占用 EXE 而报 `LNK1168`，未完成原生集成测试。用户随后确认运行时问题已解决；真实校园接口、全量手工验收和原生集成测试结果需分别记录。

## 开发排错

- **无法解析 `pointycastle` / 找不到 `AESEngine`、`KeyParameter`**：先在本目录运行 `flutter pub get`。即使 `pubspec.yaml` 和 `pubspec.lock` 已包含依赖，旧 `.dart_tool/package_config.json` 仍可能缺少映射；该文件由工具生成，不应手工编辑或提交。
- **找不到 `FileService.moveRoot`**：当前接口是 `setDownloadDirectory(String?)`，`AppServices.applyDownloadDirectory` 已委托该接口。更改目录统一写入 `settings/app.downloadDirectory`，不要恢复旧的 `downloadDir` 设置写入路径。
- **热重载后 `FileService._root` 报 `Null` 不是 `Directory`**：字段或构造初始化变动后，旧对象可能仍保留在内存中。在 `flutter run` 终端按大写 `R` 执行 Hot Restart，或停止调试后重新运行 `flutter run -d windows`。当前构造函数会初始化 `_root` 和 `_defaultRoot`；无需为旧实例加入空目录兜底。参见 [Flutter 热重载与状态保留](https://docs.flutter.dev/tools/hot-reload#previous-state-is-combined-with-new-code)。
- **Windows 链接失败 `LNK1168`，无法写入 EXE**：检查是否仍在运行相同输出路径的客户端，包括托盘中的实例。退出该客户端及相应调试会话，再重新构建或运行原生测试。

## 下载目录

默认目录为 `getApplicationSupportDirectory()` 下的 `downloads`。下载页可更改目录或恢复默认，设置页不再提供下载目录配置；启动时读取 `settings/app.downloadDirectory`。`FileService.setDownloadDirectory` 负责创建自定义目录、更新当前根目录和保存配置，`AppServices.applyDownloadDirectory` 复用同一逻辑；null、空白或默认路径会移除自定义配置并恢复 `files.defaultRoot`。

切换目录不会移动已有文件。下载记录中的 `relativePath` 与记录级 `downloadDir` 用于查找，`FileService.file()` 依次尝试记录目录、当前目录和默认目录。当前下载页 loader 的 `exists` 仅检查当前根目录，因此原目录中的文件仍可能被标为已移除；服务层查找回归通过不代表这一页面状态差异已修复。

`services.dart` 中读取旧 `settings/app.downloadDir` 并回退系统下载目录的 `downloadDirectory()` 目前只由遗留测试引用，不参与实际启动和目录切换。

## 桌面挂件

Windows 挂件使用 `desktop_multi_window` 创建一个子窗口，展示层级复刻旧 Web 挂件，但日程仍通过主窗口转发的 `upcoming()` 获取，问答仍通过 `AgentService.chat(widget: true)` 获取；问答是一次性只读模式，不写入普通聊天历史，也不能调用下载工具。

展开面板与 64×64 的“求是”小球是同一个 `WidgetApp` 的内部状态，不是两个窗口。展开时窗口为 380×560，收起时为 64×64；窗口使用透明背景、无标题栏/无边框、无阴影、置顶且不进入任务栏。点击日程或“打开应用”会唤起主窗口并跳转工作台 `/`。

`DesktopHost.initialize` 启动时扫描并复用已有的 `widget:*` 子窗口，同时隐藏重复实例，避免热重载/热重启后出现多个挂件。`windows/runner/flutter_window.cpp` 只为 `desktop_multi_window` 的 secondary window 去除 Win32 系统边框，主窗口不受影响。

## 代码导航

`lib/main.dart` 通过 `ui/pages/feature_page.dart` 路由到独立页面。工作台、课程表、作业、考试、学校信息、下载和课堂占位页各自管理 State；旧集中页面文件及兼容导出入口已删除，应用和测试直接导入所属模块。

| 路径（相对 `lib`） | 职责 |
| --- | --- |
| `ui/pages/*_page.dart` | 页面状态、筛选条件、页面上下文和组件组合 |
| `ui/shared/campus_page.dart` | 公共加载、错误展示、首次/手动刷新和缓存订阅释放 |
| `ui/courses/`、`ui/assignments/`、`ui/exams/`、`ui/downloads/`、`ui/dashboard/` | 功能组件、详情弹层和交互 |
| `ui/courses/course_overview_state.dart` | 工作台/课程页共用的辅助栏状态、刷新及弹层通知 |
| `application/page_loaders/` | 页面数据加载、缓存依赖和更新时间聚合 |
| `application/course_overview.dart`、`application/course_details.dart` | 教务网课程聚合、课程查找与课表信息补全 |
| `domain/course_catalog.dart`、`grade_stats.dart`、`assignment_rules.dart`、`timetable_options.dart`、`formatters.dart` | 课程规范化、统计、作业规则、小学期筛选和格式化 |

页面加载器和领域规则不反向依赖 UI；页面上下文模型仍在 `domain/page_context.dart`，悬浮聊天窗仍在 `ui/chat.dart`。完整页面列表和新增页面约定见 [页面模块导航](../lib/ui/pages/README.md)，仓库协作约定见 [AGENTS.md](../AGENTS.md)。

## 登录验证

账号密码只在应用设置中填写，通过系统安全存储保存。CAS、学在浙大与教务网分别持有内存 Cookie，参照 [login-zju](https://github.com/5dbwat4/login-ZJU) 的登录顺序、RSA、服务票据和回调机制实现。

公开登录页与公钥检查，不读取或提交凭据：

```powershell
flutter test tool/check_login_transport.dart
```

完整真实登录检查默认跳过。先在应用中保存真实凭据，再显式运行：

```powershell
flutter test integration_test/native_login_test.dart -d windows --dart-define=VERIFY_SAVED_CAMPUS_LOGIN=true
```

该检查只报告阶段及安全错误信息，不修改已保存的账号或业务数据。它不属于普通自动回归，避免反复向学校提交登录请求。协议 Mock 测试不能替代真实登录验收。

## 当前实现边界

- 课程表实际只有 1–13 节；目前横向自适应，但视觉网格纵向仍使用固定 52px 节次高度。代码中的额外晚间时间项属于待清理的遗留数据，不代表产品存在第 14、15 节。
- 首页学业快览与课程总览辅助栏共用 `loadCourseOverview` 的教务网课程聚合结果；教务网考签、全历史课表和成绩库负责课程数、学分、教师、成绩和绩点，学在浙大只负责建课状态及资料/作业关联。
- 每个数据页本次运行首次进入时强制绕过缓存请求；之后点击刷新或下拉刷新也强制请求。通知和校历同样接入一天缓存；通知页不使用下拉刷新，但保留强制刷新的页面按钮。数据页标题显示“数据更新于 N 分钟前”，下载页不参与这套缓存和更新时间提示。
- 相同缓存 key 的并发请求由 `CampusService` 合并，成功写入缓存后通过 `cacheChanges` 广播给其他页面；页面收到事件后按依赖从缓存重组，不再次强制联网。组合页面的更新时间取实际依赖缓存中最早的成功时间。
- `domain/page_context.dart` 统一记录当前页面、学期、辅助栏、课程详情和详情 Tab，并实时提供给 `AppServices`、聊天和 Agent 工具。
- 退出登录当前会取消 Agent 请求，但还没有统一取消 `FileService` 的活动下载。
- 工作台和课程资料弹层仍需修复错误态展示：部分路径直接展示 `snapshot.error`，课程资料请求出错时可能停留在 loading 状态。
- `test/feature_page_lifecycle_test.dart` 已覆盖路由切换、状态隔离、首次/手动刷新、缓存广播、本地下载页，以及七个功能页在 1320/800/390px 下的渲染。设置、聊天窗、多宽度 golden 和真机触控仍未完整覆盖。
- Android 的校历公开地址是 `http://calendar.celechron.top`，已在网络安全配置中作为唯一远程明文例外，并有内置校历回退；Android release 尚未配置正式签名。

## 刷新与缓存约定

页面数据的刷新入口统一由页面层和 `AppServices` 协作管理：

1. `claimInitialRefresh(pageKey)` 只允许每个页面在本次应用运行中自动强制刷新一次；辅助面板使用独立的稳定 key。
2. 首次进入不读取有效缓存，直接请求最新数据。再次进入、路由重建以及普通生命周期变化不触发自动刷新。
3. 用户主动点击刷新或下拉刷新时，必须绕过缓存重新请求；学校信息页不提供下拉刷新，只提供页面刷新按钮。
4. 网络请求成功后写入带更新时间的缓存，默认有效期为一天；失败时可以回退到过期缓存，但必须标记 `stale` 并保留失败信息。
5. 通知的素质拓展和教务网两个来源分别缓存、分别失败和回退，不能因为一个来源失败而丢失另一个来源的数据。
6. 下载页只管理本地文件和下载状态，不参与网络数据缓存、首次进入刷新和“数据更新于 N 分钟前”提示。
7. `CampusService` 对相同缓存 key 做请求去重，并通过 `cacheChanges` 广播成功写入；页面更新时间只依赖实际展示的数据，不得使用页面重组时间或无关历史缓存时间。
8. 组合数据取实际依赖缓存中最早的成功时间。工作台若仍依赖 `CampusService.stale` 中的资源，通过 `_hasStaleData` 显示部分刷新失败提示，不能把失败回退显示成“刚刚更新”。
9. `CampusPageState.refresh` 和辅助栏刷新在结束时同步更新状态。辅助弹层通过 `overviewChanges` 与 `ListenableBuilder` 接收数据 Future、学期和刷新状态变化，不能只依赖宿主页面的 `setState`。

课表刷新解析位于 `application/campus.dart`：遍历响应中的附加元数据时先判断是否为列表，只处理其中的 Map 条目；缺失的 `sjkList` 按空列表处理，避免把标量/对象当列表解析失败后持续回退旧课表缓存。成功写入仍是推进缓存更新时间的唯一依据。

不要在单个 widget 内重新实现缓存或用生命周期回调替代页面刷新闸门；修改刷新逻辑时应同时覆盖首次进入、重复进入、手动刷新、通知栏展开/收起和网络失败回退。

2026-09-10：修复 Cookie `Expires` 的严格日期解析引发 `HttpException`、导致设置页仅显示通用失败提示的问题。新增兼容 Cookie 日期解析、登录响应回归，以及区分凭据读取、保存、会话清理和认证阶段的错误提示。Windows 原生安全存储和后台 SQLite 验证通过；用户已确认应用登录流程通过，后续重点转为各页面与旧 Web 版的功能验收。
