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

2026-09-11 升级：`go_router` 18.0.1、`file_picker` 12.2.0、`flutter_secure_storage` 11.1.0、`drift` 2.35.0，以及可兼容的间接依赖。Markdown 切换到维护中的 `flutter_markdown_plus` 1.0.12，移除未使用的 `cookie_jar`。

- 文件选择使用 `pickFile()` / `readAsBytes()`；`saveFile()` 在各平台自行保存并返回 URI，应用不再重复写文件。参见 [file_picker 12 变更](https://pub.dev/packages/file_picker/changelog)。
- 安全存储升级不使用 v10 已废弃的加密配置。Android 最低 API 24，由当前 Flutter 的 `minSdkVersion` 提供；Windows 使用 DPAPI。参见 [安全存储变更](https://pub.dev/packages/flutter_secure_storage/changelog)。
- `archive` 3.6.1、`xml` 6.6.1 暂保留：Excel 4.0.6 对它们分别约束为 `^3.6.1` 和 `<7.0.0`。升级需另行迁移 Excel 库，不能通过 `dependency_overrides` 强行跨版本。
- `material_color_utilities` 0.13.0 与 `test_api` 0.7.12 由当前 Flutter SDK 固定，随 SDK 更新处理。`flutter pub outdated` 仍显示这四项属于预期。

依赖兼容测试在 `test/dependency_compatibility_test.dart`，覆盖 Markdown 表格及链接导航、保存取消与 Android content URI；原生安全存储和 SQLite 测试见 `integration_test/native_storage_test.dart`。

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

2026-09-10：修复 Cookie `Expires` 的严格日期解析引发 `HttpException`、导致设置页仅显示通用失败提示的问题。新增兼容 Cookie 日期解析、登录响应回归，以及区分凭据读取、保存、会话清理和认证阶段的错误提示。Windows 原生安全存储和后台 SQLite 验证通过；用户已确认应用登录流程通过，后续重点转为各页面与旧 Web 版的功能验收。
