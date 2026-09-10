// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/platform/operation_error.dart';

/// Opt-in real verification. Credentials must already have been entered in the app.
/// Does not change saved credentials or business data, or print HTTP payloads.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('saved campus credentials: native login', (_) async {
    final session = CampusSession(SecureSecrets());
    var stage = '统一认证';
    try {
      await session.ensure('cas');
      print('PASS: CAS');
      stage = '学在浙大登录';
      await session.ensure('courses');
      print('PASS: courses login');
      stage = '教务网登录';
      await session.ensure('zdbk');
      print('PASS: zdbk login');
    } catch (e, stack) {
      print(operationError(e, stage));
      print(stack);
      fail('Native login failed in $stage (${e.runtimeType})');
    } finally {
      await session.reset();
      session.dio.close(force: true);
    }
  }, skip: !const bool.fromEnvironment('VERIFY_SAVED_CAMPUS_LOGIN'));
}
