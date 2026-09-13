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
import 'package:zju_campus_agent/ui/settings.dart';

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
  testWidgets('SettingsPage can collapse and expand model and persona cards',
      (tester) async {
    final db = AgentDatabase.memory();
    final secrets = _FakeSecrets();
    await secrets.write('providers', {
      'items': [
        {
          'id': 'p1',
          'name': 'DeepSeek',
          'baseUrl': 'https://api.deepseek.com',
          'model': 'deepseek-chat',
          'apiKey': 'sk-test',
          'protocol': 'openai',
          'enabled': true,
        },
      ],
    });
    await db.put('settings', 'app', {
      'nickname': '求是学子',
      'personaPrompt': '浙大本科生',
    });

    final campus = CampusService(CampusSession(secrets), db);
    final tempDir = Directory.systemTemp.createTempSync('settings_test_');
    final files = FileService(campus, tempDir);
    final backups = BackupService(db, files);
    final agent = AgentService(
      campus,
      files,
      GuideIndex(const {}),
    );

    final services = AppServices(db, secrets, campus, files, backups, agent);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsPage(services: services),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('贰 · 模型来源'), findsOneWidget);
    expect(find.text('DeepSeek · deepseek-chat'), findsOneWidget);
    expect(find.text('保存来源'), findsNothing);

    expect(find.text('叁 · 个性化'), findsOneWidget);
    expect(find.text('昵称：求是学子'), findsOneWidget);
    expect(find.text('保存个性化'), findsNothing);

    await tester.tap(find.text('贰 · 模型来源'));
    await tester.pumpAndSettle();
    expect(find.text('保存来源'), findsOneWidget);

    await tester.tap(find.text('贰 · 模型来源'));
    await tester.pumpAndSettle();
    expect(find.text('保存来源'), findsNothing);

    await tester.tap(find.text('叁 · 个性化'));
    await tester.pumpAndSettle();
    expect(find.text('保存个性化'), findsOneWidget);

    await tester.tap(find.text('叁 · 个性化'));
    await tester.pumpAndSettle();
    expect(find.text('保存个性化'), findsNothing);

    tempDir.deleteSync(recursive: true);
    await db.close();
  });

  testWidgets('SettingsPage expands model card by default when no provider or in setup mode',
      (tester) async {
    final db = AgentDatabase.memory();
    final secrets = _FakeSecrets();
    final campus = CampusService(CampusSession(secrets), db);
    final tempDir = Directory.systemTemp.createTempSync('settings_test_');
    final files = FileService(campus, tempDir);
    final backups = BackupService(db, files);
    final agent = AgentService(
      campus,
      files,
      GuideIndex(const {}),
    );

    final services = AppServices(db, secrets, campus, files, backups, agent);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsPage(services: services, setup: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('贰 · 模型来源'), findsOneWidget);
    // When setup mode or empty providers, it is expanded by default
    expect(find.text('保存来源'), findsOneWidget);

    tempDir.deleteSync(recursive: true);
    await db.close();
  });
}
