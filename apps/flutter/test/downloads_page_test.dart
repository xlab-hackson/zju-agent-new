import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/application/agent.dart';
import 'package:zju_campus_agent/application/campus.dart';
import 'package:zju_campus_agent/application/files.dart';
import 'package:zju_campus_agent/application/knowledge.dart';
import 'package:zju_campus_agent/application/services.dart';
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/database.dart';
import 'package:zju_campus_agent/domain/models.dart';
import 'package:zju_campus_agent/ui/pages/downloads_page.dart';

class _FakeSecrets implements SecretStore {
  final Map<String, Json> data = {};
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<Json?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Json value) async => data[key] = value;
}

void main() {
  testWidgets('DownloadsPage displays download directory card and allows configuration', (
    tester,
  ) async {
    final db = AgentDatabase.memory();
    addTearDown(() => db.close());
    final secrets = _FakeSecrets();
    final campus = CampusService(CampusSession(secrets), db);

    final defaultDir = Directory.systemTemp.createTempSync('zju_default_dl_');
    addTearDown(() => defaultDir.deleteSync(recursive: true));

    final customDir = Directory.systemTemp.createTempSync('zju_custom_dl_target_');
    addTearDown(() => customDir.deleteSync(recursive: true));

    final files = FileService(campus, defaultDir, defaultRoot: defaultDir);
    final backups = BackupService(db, files);
    final agent = AgentService(campus, files, GuideIndex(const {}));
    final services = AppServices(db, secrets, campus, files, backups, agent);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadsPage(services: services),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initial State: Default directory shown with '默认' badge
    expect(find.text('下载保存目录'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('自定义'), findsNothing);
    expect(find.text(defaultDir.path), findsOneWidget);
    expect(find.text('打开目录'), findsOneWidget);
    expect(find.text('更改目录'), findsOneWidget);
    expect(find.text('恢复默认'), findsNothing);

    // 2. Click '更改目录' to open config dialog
    await tester.tap(find.text('更改目录'));
    await tester.pumpAndSettle();

    expect(find.text('配置下载目标目录'), findsOneWidget);
    expect(find.text('新下载的课件、资料将保存到此目录。各课程将以课程名作为子文件夹分类存放。'), findsOneWidget);
    expect(find.text('浏览...'), findsOneWidget);
    expect(find.text('填入默认'), findsOneWidget);

    // 3. Enter new custom directory in TextField
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    await tester.enterText(textField, customDir.path);
    await tester.pumpAndSettle();

    // 4. Click '保存' in dialog
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 5. Verify custom directory is applied
    expect(find.text('配置下载目标目录'), findsNothing); // Dialog closed
    expect(files.isCustomDirectory, isTrue);
    expect(files.root.path, customDir.path);

    // Verify UI reflects custom state
    expect(find.text('自定义'), findsOneWidget);
    expect(find.text(customDir.path), findsOneWidget);
    expect(find.text('恢复默认'), findsOneWidget);

    // Verify database saved the setting
    final savedSettings = await db.get('settings', 'app');
    expect(savedSettings?['downloadDirectory'], customDir.path);

    // 6. Click '恢复默认'
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    // 7. Verify directory reverted to default
    expect(files.isCustomDirectory, isFalse);
    expect(files.root.path, defaultDir.path);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('自定义'), findsNothing);
    expect(find.text(defaultDir.path), findsOneWidget);
    expect(find.text('恢复默认'), findsNothing);

    final resetSettings = await db.get('settings', 'app');
    expect(resetSettings?.containsKey('downloadDirectory') ?? false, isFalse);
  });
}
