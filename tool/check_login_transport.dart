// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/data/login_cookie_jar.dart';

// Public endpoints only. Never reads or submits a user's credentials.
void main() {
  test('public login transport (no credentials)', checkLoginTransport);
}

Future<void> checkLoginTransport() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  final jar = LoginCookieJar();
  for (final path in ['login', 'v2/getPubKey']) {
    final uri = Uri.parse('https://zjuam.zju.edu.cn/cas/$path');
    try {
      final response = await dio.get<String>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          headers: {'User-Agent': campusUserAgent, 'Cookie': jar.header(uri)},
        ),
      );
      jar.store(uri, response.headers['set-cookie'] ?? []);
      if (path == 'login') {
        final execution = html
            .parse(response.data)
            .querySelector('input[name="execution"]');
        print(
          'login: HTTP ${response.statusCode}, execution=${execution != null}',
        );
      } else {
        final key = jsonDecode(response.data!) as Map<String, dynamic>;
        encryptCampusPassword(
          'transport-test',
          key['exponent'] as String,
          key['modulus'] as String,
        );
        print('public key: HTTP ${response.statusCode}, RSA valid');
      }
    } catch (e, stack) {
      print('$path: ${e.runtimeType}');
      // Stack frames contain code locations, not exception values or HTTP headers.
      print(stack);
      fail('Public endpoint check failed: ${e.runtimeType}');
    }
  }
  dio.close();
}
