// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zju_campus_agent/application/agent.dart';
import 'package:zju_campus_agent/application/campus.dart';
import 'package:zju_campus_agent/application/files.dart';
import 'package:zju_campus_agent/application/knowledge.dart';
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/database.dart';
import 'package:zju_campus_agent/domain/models.dart';

class _ConnectionProbe extends AgentService {
  _ConnectionProbe(CampusService campus, FileService files)
    : super(campus, files, GuideIndex({}));
  @override
  Future<Object?> execute(String name, Json input) async {
    // Do not query campus data or download files in a connectivity check.
    throw const AppError('TOOL_FORBIDDEN', '连通性检查不执行工具，请直接回答。');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('saved model configuration completes native Agent streaming', (
    _,
  ) async {
    final db = AgentDatabase.memory();
    final directory = await Directory.systemTemp.createTemp('zju_model_probe_');
    final campus = CampusService(CampusSession(SecureSecrets()), db);
    final agent = _ConnectionProbe(campus, FileService(campus, directory));
    var hasText = false, done = false;
    try {
      await for (final event in agent.chat(
        '这是客户端流式连通性测试。请只回复“连接成功”，不要调用工具。',
        widget: true,
      )) {
        if (event.type == 'error') {
          print(
            'Model check: ${event.data['code']} / ${event.data['message']}',
          );
          fail('Configured model did not complete: ${event.data['code']}');
        }
        if (event.type == 'text' && text(event.data, 'delta').isNotEmpty)
          hasText = true;
        if (event.type == 'done') done = event.data['paused'] == false;
      }
      expect(hasText, isTrue);
      expect(done, isTrue);
      expect(await db.list('messages'), isEmpty);
      print(
        'PASS: configured model -> native byte stream -> Agent -> done; no history saved',
      );
    } finally {
      agent.cancelAll();
      agent.model.dio.close(force: true);
      campus.publicClient.close(force: true);
      await campus.session.reset();
      campus.session.dio.close(force: true);
      await db.close();
      await directory.delete(recursive: true);
    }
  }, skip: !const bool.fromEnvironment('VERIFY_SAVED_MODEL'));
}
