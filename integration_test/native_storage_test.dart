import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native secure storage round trip and missing deletion', (
    _,
  ) async {
    final secrets = SecureSecrets();
    final key = 'integration_probe_${DateTime.now().microsecondsSinceEpoch}';
    try {
      expect(await secrets.read(key), isNull);
      await secrets.delete(key);
      await secrets.write(key, {'probe': 'non-secret-test-value'});
      expect(await secrets.read(key), {'probe': 'non-secret-test-value'});
      await secrets.delete(key);
      expect(await secrets.read(key), isNull);
    } finally {
      await secrets.delete(key);
    }
  });
  testWidgets('native background SQLite round trip', (_) async {
    final directory = await Directory.systemTemp.createTemp('zju_db_test_');
    final db = AgentDatabase(File('${directory.path}/agent.db'));
    try {
      await db.put('cache', 'probe', {'value': 1});
      expect(await db.get('cache', 'probe'), {'value': 1});
      await db.remove('cache');
      expect(await db.list('cache'), isEmpty);
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
