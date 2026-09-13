import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/data/database.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/domain/models.dart';
import 'package:zju_campus_agent/application/campus.dart';
import 'package:zju_campus_agent/application/files.dart';
import 'package:zju_campus_agent/application/agent.dart';
import 'package:zju_campus_agent/application/knowledge.dart';
import 'package:zju_campus_agent/application/services.dart';

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

class DeferredDownloadAdapter implements HttpClientAdapter {
  DeferredDownloadAdapter(this.body);
  final StreamController<Uint8List> body;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    if (calls == 1) {
      return ResponseBody.fromString('<html>课程主页</html>', 200);
    }
    return ResponseBody(
      body.stream,
      200,
      headers: {
        'content-type': ['application/octet-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
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
  test(
    'download paths are grouped by course and suffix duplicate names',
    () async {
      final first = File(confinedPath(root.path, '高等数学/讲义.pdf'));
      await first.parent.create(recursive: true);
      await first.create();
      expect(
        await availableDownloadPath(root.path, '高等数学', '讲义.pdf'),
        '高等数学/讲义 (1).pdf',
      );
      final second = File(confinedPath(root.path, '高等数学/讲义 (1).pdf'));
      await second.create();
      expect(
        await availableDownloadPath(root.path, '高等数学', '讲义.pdf'),
        '高等数学/讲义 (2).pdf',
      );
    },
  );
  test(
    'duplicate active downloads share one stream and deletion cancels it',
    () async {
      final body = StreamController<Uint8List>();
      final adapter = DeferredDownloadAdapter(body);
      final campus = CampusService(
        CampusSession(
          MemorySecrets(),
          client: Dio()..httpClientAdapter = adapter,
        ),
        db,
      );
      final files = FileService(campus, root);
      final input = {
        'courseId': 'course-1',
        'courseName': '测试课程',
        'fileId': 'file-1',
        'fileName': 'large.bin',
      };
      final first = files.download(input);
      final second = files.download(input);
      expect(identical(first, second), isTrue);
      for (var i = 0; i < 20 && adapter.calls < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(adapter.calls, 2);
      final record = (await db.list('downloads')).single;
      await files.delete(record, purge: true);
      await expectLater(
        first,
        throwsA(isA<AppError>().having((e) => e.code, 'code', 'CANCELLED')),
      );
      expect(await db.list('downloads'), isEmpty);
      await body.close();
    },
  );
  test('tool schemas enforce required fields and batch bounds', () {
    expect(agent.toolDefinitions().length, 15);
    expect(agent.toolDefinitions(readOnly: true).length, 13);
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

  test(
    'FileService supports configuring custom download directory and resetting to default',
    () async {
      final customDir = await Directory.systemTemp.createTemp('zju_custom_dl_');
      addTearDown(() => customDir.delete(recursive: true));

      final campus = CampusService(CampusSession(MemorySecrets()), db);
      final files = FileService(campus, root, defaultRoot: root);

      expect(files.isCustomDirectory, isFalse);
      expect(files.root.path, root.path);
      expect(files.defaultRoot.path, root.path);

      // Set custom directory
      await files.setDownloadDirectory(customDir.path);
      expect(files.isCustomDirectory, isTrue);
      expect(files.root.path, customDir.path);

      // Check persistence in settings:app
      final settings = await db.get('settings', 'app');
      expect(settings?['downloadDirectory'], customDir.path);

      // Reset back to default
      await files.setDownloadDirectory(null);
      expect(files.isCustomDirectory, isFalse);
      expect(files.root.path, root.path);
      final resetSettings = await db.get('settings', 'app');
      expect(resetSettings?.containsKey('downloadDirectory') ?? false, isFalse);
    },
  );

  test(
    'AppServices applies and resets the same download directory as FileService',
    () async {
      final files = backups.files;
      final services = AppServices(
        db,
        MemorySecrets(),
        files.campus,
        files,
        backups,
        agent,
      );
      final customDir = Directory(confinedPath(root.path, 'custom'));
      await db.put('settings', 'app', {'nickname': '测试'});
      final oldFile = File(confinedPath(root.path, '课程/讲义.pdf'));
      await oldFile.parent.create(recursive: true);
      await oldFile.writeAsString('existing download');
      final record = {
        'relativePath': '课程/讲义.pdf',
        'downloadDir': root.path,
      };

      final selected = await services.applyDownloadDirectory(
        '  ${customDir.path}  ',
      );
      expect(selected.path, customDir.path);
      expect(files.root.path, customDir.path);
      expect(await customDir.exists(), isTrue);
      expect(await db.get('settings', 'app'), {
        'nickname': '测试',
        'downloadDirectory': customDir.path,
      });
      expect((await files.file(record)).path, oldFile.path);

      for (final reset in <String?>[null, '   ', files.defaultRoot.path]) {
        await services.applyDownloadDirectory(customDir.path);
        final restored = await services.applyDownloadDirectory(reset);
        expect(restored.path, files.defaultRoot.path);
        expect(files.isCustomDirectory, isFalse);
        expect(await db.get('settings', 'app'), {'nickname': '测试'});
        expect((await files.file(record)).path, oldFile.path);
      }
    },
  );

  test(
    'FileService file lookup checks recorded downloadDir and fallbacks',
    () async {
      final customDir = await Directory.systemTemp.createTemp('zju_custom_dl2_');
      addTearDown(() => customDir.delete(recursive: true));

      final campus = CampusService(CampusSession(MemorySecrets()), db);
      final files = FileService(campus, customDir, defaultRoot: root);

      // Create a file in default root (representing a previously downloaded file before changing dir)
      final oldFile = File(confinedPath(root.path, '高等数学/ch1.pdf'));
      await oldFile.parent.create(recursive: true);
      await oldFile.writeAsString('old content');

      // Create a file in customDir
      final newFile = File(confinedPath(customDir.path, '线性代数/ch2.pdf'));
      await newFile.parent.create(recursive: true);
      await newFile.writeAsString('new content');

      // 1. Record with explicit downloadDir matching root
      final recOld = {
        'id': 'd1',
        'relativePath': '高等数学/ch1.pdf',
        'downloadDir': root.path,
      };
      final resolvedOld = await files.file(recOld);
      expect(resolvedOld.path, oldFile.path);

      // 2. Record with no downloadDir (legacy), resolves from fallback defaultRoot
      final recLegacy = {
        'id': 'd2',
        'relativePath': '高等数学/ch1.pdf',
      };
      final resolvedLegacy = await files.file(recLegacy);
      expect(resolvedLegacy.path, oldFile.path);

      // 3. Record in current custom root
      final recNew = {
        'id': 'd3',
        'relativePath': '线性代数/ch2.pdf',
        'downloadDir': customDir.path,
      };
      final resolvedNew = await files.file(recNew);
      expect(resolvedNew.path, newFile.path);
    },
  );
}
