import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/platform/operation_error.dart';

void main() {
  test('diagnostics show stage and type without exception payloads', () {
    for (final error in [
      const HttpException('secret-cookie'),
      const FileSystemException('secret-password', 'secret-path'),
      PlatformException(code: 'secret-token', message: 'secret-api-key'),
      const FormatException('secret-password'),
    ]) {
      final result = operationError(error, '登录');
      expect(result, startsWith('登录失败：'));
      expect(result, isNot(contains('secret')));
    }
    expect(
      operationError(const HttpException('secret'), '登录'),
      contains('HttpException'),
    );
  });
}
