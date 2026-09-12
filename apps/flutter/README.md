# 求是书院 · Flutter 客户端

校园认证、校园接口、模型请求与本地数据库均在客户端运行，不需要 Node 或本地业务 HTTP 服务。当前仍在迁移和验收阶段；Windows 已能原生编译，Android 及全量功能验收尚未完成。旧数据导入已按需求取消。

## 运行与检查

要求 Flutter >=3.44、Dart >=3.12（与 go_router 18 的最低要求一致）。依赖版本由 `pubspec.lock` 固定，请提交锁文件以保持 Windows 和 Android 构建一致。

在本目录执行（仓库内的 Flutter 为 `../../.tooling/flutter/bin/flutter.bat`）：

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

依赖兼容测试在 `test/dependency_compatibility_test.dart`，覆盖 Markdown 表格及链接导航、保存取消与 Android content URI；原生安全存储和 SQLite 测试见 `integration_test/native_storage_test.dart`。2026-09-11 扫描时 `flutter test` 为 39 项全通过，`flutter analyze` 无 error 但有 18 条 info 级风格/弃用提示。

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
- 每个数据页本次运行首次进入时强制绕过缓存请求；之后点击刷新或下拉刷新也强制请求。通知和校历同样接入一天缓存；通知页不使用下拉刷新，但保留强制刷新的页面按钮。数据页标题显示“数据更新于 N 分钟前”，下载页不参与这套缓存和更新时间提示。
- 退出登录当前会取消 Agent 请求，但还没有统一取消 `FileService` 的活动下载。
- 工作台和课程资料弹层仍需修复错误态展示：部分路径直接展示 `snapshot.error`，课程资料请求出错时可能停留在 loading 状态。工作台、课表、设置和聊天窗也尚无完整的多宽度 widget overflow 自动回归。
- Android 的校历公开地址是 `http://calendar.celechron.top`，已在网络安全配置中作为唯一远程明文例外，并有内置校历回退；Android release 尚未配置正式签名。

## 刷新与缓存约定

页面数据的刷新入口统一由页面层和 `AppServices` 协作管理：

1. `claimInitialRefresh(pageKey)` 只允许每个页面在本次应用运行中自动强制刷新一次；辅助面板使用独立的稳定 key。
2. 首次进入不读取有效缓存，直接请求最新数据。再次进入、路由重建以及普通生命周期变化不触发自动刷新。
3. 用户主动点击刷新或下拉刷新时，必须绕过缓存重新请求；学校信息页不提供下拉刷新，只提供页面刷新按钮。
4. 网络请求成功后写入带更新时间的缓存，默认有效期为一天；失败时可以回退到过期缓存，但必须标记 `stale` 并保留失败信息。
5. 通知的素质拓展和教务网两个来源分别缓存、分别失败和回退，不能因为一个来源失败而丢失另一个来源的数据。
6. 下载页只管理本地文件和下载状态，不参与网络数据缓存、首次进入刷新和“数据更新于 N 分钟前”提示。

不要在单个 widget 内重新实现缓存或用生命周期回调替代页面刷新闸门；修改刷新逻辑时应同时覆盖首次进入、重复进入、手动刷新、通知栏展开/收起和网络失败回退。

2026-09-10：修复 Cookie `Expires` 的严格日期解析引发 `HttpException`、导致设置页仅显示通用失败提示的问题。新增兼容 Cookie 日期解析、登录响应回归，以及区分凭据读取、保存、会话清理和认证阶段的错误提示。Windows 原生安全存储和后台 SQLite 验证通过；用户已确认应用登录流程通过，后续重点转为各页面与旧 Web 版的功能验收。
