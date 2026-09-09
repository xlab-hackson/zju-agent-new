import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/data/database.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/domain/models.dart';
import 'package:zju_campus_agent/application/campus.dart';
import 'package:zju_campus_agent/application/files.dart';
import 'package:zju_campus_agent/application/agent.dart';
import 'package:zju_campus_agent/application/knowledge.dart';

class MemorySecrets implements SecretStore {
  final Map<String, Json> values = {};
  @override
  Future<Json?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Json value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  late AgentDatabase db;
  late Directory root;
  late BackupService backups;
  late AgentService agent;
  setUp(() async {
    db = AgentDatabase.memory();
    root = await Directory.systemTemp.createTemp('zju_test_');
    final campus = CampusService(CampusSession(MemorySecrets()), db),
        files = FileService(campus, root);
    backups = BackupService(db, files);
    agent = AgentService(campus, files, GuideIndex({}));
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test(
    'backup strips credentials and session state; restore is idempotent',
    () async {
      await db.put('settings', 'app', {
        'nickname': '测试',
        'accessToken': 'secret',
        'apiKey': 'secret',
      });
      await db.put('cache', 'private', {'value': 'private'});
      await db.put('confirmations', 'pending', {'input': 'download'});
      await db.put('conversations', 'c', {'id': 'c', 'title': '学习'});
      final bytes = await backups.export();
      final archive = ZipDecoder().decodeBytes(bytes);
      final manifest = utf8.decode(
        archive.findFile('manifest.json')!.content as List<int>,
      );
      expect(manifest, contains('测试'));
      expect(manifest, isNot(contains('secret')));
      expect(manifest, isNot(contains('private')));
      await db.remove('conversations');
      await backups.restore(bytes);
      await backups.restore(bytes);
      expect((await db.list('conversations')).length, 1);
    },
  );
  test('zip traversal rejected before any database write', () async {
    final archive = Archive()..addFile(ArchiveFile('../escape.txt', 1, [65]));
    await expectLater(
      backups.restore(ZipEncoder().encode(archive)!),
      throwsA(isA<AppError>()),
    );
    expect(await db.list('conversations'), isEmpty);
    expect(
      () => confinedPath(root.path, 'C:/outside'),
      throwsA(isA<AppError>()),
    );
    expect(
      () => confinedPath(root.path, 'x/../../outside'),
      throwsA(isA<AppError>()),
    );
  });
  test('tool schemas enforce required fields and batch bounds', () {
    expect(agent.toolDefinitions().length, 14);
    expect(agent.toolDefinitions(readOnly: true).length, 12);
    expect(
      () => agent.validate('zju_download_course_material', {'fileId': '1'}),
      throwsA(isA<AppError>()),
    );
    expect(
      () => agent.validate('zju_batch_download', {'files': []}),
      throwsA(isA<AppError>()),
    );
    expect(
      () => agent.validate('zju_get_courses', {'unexpected': true}),
      throwsA(isA<AppError>()),
    );
  });
  test(
    'confirmation is bound to conversation and consumed only once',
    () async {
      await db.put('confirmations', 'p', {
        'id': 'p',
        'conversationId': 'c',
        'status': 'pending',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 1))
            .toIso8601String(),
        'round': 8,
        'calls': [
          {
            'id': 't',
            'name': 'zju_download_course_material',
            'input': {'courseId': '1', 'fileId': '1', 'fileName': 'a.pdf'},
          },
        ],
      });
      final wrong = await agent.confirm('other', 'p', true).toList();
      expect(wrong.single.data['code'], 'CONFIRMATION_INVALID');
      expect((await db.get('confirmations', 'p'))!['status'], 'pending');
      await agent.confirm('c', 'p', false).toList();
      expect((await db.get('confirmations', 'p'))!['status'], 'consumed');
      final again = await agent.confirm('c', 'p', true).toList();
      expect(again.single.data['code'], 'CONFIRMATION_INVALID');
      expect(await db.list('downloads'), isEmpty);
      expect((await db.list('messages')).length, 1);
    },
  );
}
