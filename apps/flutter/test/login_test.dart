import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/login_cookie_jar.dart';
import 'package:zju_campus_agent/domain/models.dart';

const cas = 'https://zjuam.zju.edu.cn/cas';
const courses = 'https://courses.zju.edu.cn';
const zdbk = 'https://zdbk.zju.edu.cn/jwglxt';

class Secrets implements SecretStore {
  @override
  Future<Json?> read(String key) async => {
    'username': '12345',
    'password': 'A',
  };
  @override
  Future<void> write(String key, Json value) async {}
  @override
  Future<void> delete(String key) async {}
}

class Step {
  Step(
    this.method,
    this.url,
    this.body, {
    this.status = 200,
    this.headers = const {},
    this.check,
  });
  final String method, url, body;
  final int status;
  final Map<String, List<String>> headers;
  final void Function(RequestOptions, String)? check;
}

class ScriptAdapter implements HttpClientAdapter {
  ScriptAdapter(this.steps);
  final List<Step> steps;
  int cursor = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    final payload = stream == null
        ? ''
        : utf8.decode(await stream.expand((e) => e).toList());
    if (cursor >= steps.length) {
      fail('Unexpected ${options.method} ${options.uri.path}');
    }
    final step = steps[cursor++];
    expect(options.method, step.method);
    expect(options.uri.toString(), step.url);
    expect(options.followRedirects, false);
    step.check?.call(options, payload);
    return ResponseBody.fromString(
      step.body,
      step.status,
      headers: step.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

String cookie(RequestOptions o) => '${o.headers['Cookie'] ?? ''}';
List<Step> passwordLogin(String url, {String ticket = '$cas/done'}) => [
  Step(
    'GET',
    url,
    '<input value="exec" name="execution">',
    headers: {
      'set-cookie': ['CAS=secret; Domain=.zju.edu.cn; Path=/; Secure'],
    },
    check: (o, _) {
      expect(o.headers.containsKey('X-Requested-With'), false);
    },
  ),
  Step(
    'GET',
    '$cas/v2/getPubKey',
    '{"exponent":"03","modulus":"0ca1"}',
    check: (o, _) {
      expect(cookie(o), 'CAS=secret');
    },
  ),
  Step(
    'POST',
    url,
    '',
    status: 302,
    headers: {
      'location': [ticket],
    },
    check: (o, body) {
      expect(
        body,
        'username=12345&password=0bed&execution=exec&_eventId=submit&authcode=',
      );
      expect(cookie(o), 'CAS=secret');
      expect(o.headers['User-Agent'], contains('Chrome/131'));
      expect(o.headers.containsKey('X-Requested-With'), false);
    },
  ),
];
void main() {
  test(
    'CAS failure with a hyphenated expiry retains the server error',
    () async {
      final adapter = ScriptAdapter([
        ...passwordLogin('$cas/login').take(2),
        Step(
          'POST',
          '$cas/login',
          '<span id="msg">用户名或密码错误</span>',
          headers: {
            'set-cookie': [
              'TGC=deleted; Path=/cas; Expires=Thu, 01-Jan-1970 00:00:00 GMT',
            ],
          },
        ),
      ]);
      final session = CampusSession(
        Secrets(),
        client: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        session.ensure('cas'),
        throwsA(
          isA<AppError>()
              .having((e) => e.code, 'code', 'ZJU_AUTH_FAILED')
              .having((e) => e.message, 'message', contains('用户名或密码错误')),
        ),
      );
      expect(adapter.cursor, 3);
    },
  );
  test(
    'upstream independent jars, CAS reuse, service extraction and courses meta refresh',
    () async {
      final service = '$courses/callback?next=/user/index',
          auth = '$cas/login?service=${Uri.encodeComponent(service)}';
      final adapter = ScriptAdapter([
        ...passwordLogin('$cas/login'),
        Step(
          'GET',
          '$courses/user/index',
          '',
          status: 302,
          headers: {
            'location': ['$auth&renew=true'],
            'set-cookie': ['COURSES=local; Domain=.zju.edu.cn; Path=/'],
          },
          check: (o, _) {
            expect(cookie(o), '');
            expect(o.headers.containsKey('X-Requested-With'), false);
          },
        ),
        Step(
          'GET',
          auth,
          '',
          status: 302,
          headers: {
            'location': ['$service&ticket=ST-1'],
          },
          check: (o, _) {
            expect(cookie(o), 'CAS=secret');
          },
        ),
        Step(
          'GET',
          '$service&ticket=ST-1',
          '<meta http-equiv="refresh" content="0;URL=$courses/">',
          check: (o, _) {
            expect(cookie(o), 'COURSES=local');
          },
        ),
        Step('GET', '$courses/', '<html>学在浙大</html>'),
        Step(
          'GET',
          '$courses/api/my-semesters',
          '{"semesters":[]}',
          check: (o, _) {
            expect(cookie(o), 'COURSES=local');
          },
        ),
        Step('GET', '$courses/api/my-semesters', '{"semesters":[]}'),
      ]);
      final session = CampusSession(
        Secrets(),
        client: Dio()..httpClientAdapter = adapter,
      );
      await session.ensure('cas');
      await session.json('courses', '$courses/api/my-semesters');
      await session.json('courses', '$courses/api/my-semesters');
      expect(adapter.cursor, adapter.steps.length);
    },
  );
  test(
    'zdbk initialization, strict callback and expired-session single retry',
    () async {
      final auth =
          '$cas/login?service=${Uri.encodeComponent('$zdbk/xtgl/login_ssologin.html')}';
      final callback = '$zdbk/xtgl/login_ssologin.html?ticket=ST-1';
      final adapter = ScriptAdapter([
        Step(
          'POST',
          '$zdbk/xtgl/login_cxSsoLoginUrl.html',
          '{}',
          headers: {
            'set-cookie': ['JSESSIONPREJSDM=one; Path=/'],
          },
          check: (o, _) {
            expect(o.headers.containsKey('X-Requested-With'), false);
          },
        ),
        ...passwordLogin(auth, ticket: callback),
        Step(
          'GET',
          callback,
          '',
          status: 302,
          headers: {
            'location': ['$zdbk/xtgl/index_initMenu.html'],
          },
          check: (o, _) {
            expect(cookie(o), 'JSESSIONPREJSDM=one');
          },
        ),
        Step(
          'POST',
          '$zdbk/api',
          '',
          status: 901,
          check: (o, body) {
            expect(o.headers['X-Requested-With'], 'XMLHttpRequest');
            expect(body, 'xnm=2026');
          },
        ),
        Step(
          'POST',
          '$zdbk/xtgl/login_cxSsoLoginUrl.html',
          '{}',
          headers: {
            'set-cookie': ['JSESSIONPREJSDM=two; Path=/'],
          },
        ),
        Step(
          'GET',
          auth,
          '',
          status: 302,
          headers: {
            'location': [callback],
          },
          check: (o, _) {
            expect(cookie(o), 'CAS=secret');
          },
        ),
        Step(
          'GET',
          callback,
          '',
          status: 302,
          headers: {
            'location': ['$zdbk/xtgl/index_initMenu.html'],
          },
        ),
        Step(
          'POST',
          '$zdbk/api',
          '{"kbList":[]}',
          check: (o, _) {
            expect(cookie(o), 'JSESSIONPREJSDM=two');
          },
        ),
      ]);
      final session = CampusSession(
        Secrets(),
        client: Dio()..httpClientAdapter = adapter,
      );
      expect(
        (await session.json(
          'zdbk',
          '$zdbk/api',
          method: 'POST',
          data: {'xnm': '2026'},
        ))['kbList'],
        [],
      );
      expect(adapter.cursor, adapter.steps.length);
    },
  );
  test(
    'CAS HTTP 200 probe repeats page GET before fresh password POST',
    () async {
      final auth =
          '$cas/login?service=${Uri.encodeComponent('$zdbk/xtgl/login_ssologin.html')}';
      final adapter = ScriptAdapter([
        ...passwordLogin('$cas/login'),
        Step('POST', '$zdbk/xtgl/login_cxSsoLoginUrl.html', '{}'),
        Step('GET', auth, '<input name="execution" value="stale">'),
        ...passwordLogin(auth, ticket: '$zdbk/callback'),
        Step(
          'GET',
          '$zdbk/callback',
          '',
          status: 302,
          headers: {
            'location': ['$zdbk/xtgl/index_initMenu.html'],
          },
        ),
      ]);
      final session = CampusSession(
        Secrets(),
        client: Dio()..httpClientAdapter = adapter,
      );
      await session.ensure('cas');
      await session.ensure('zdbk');
      expect(adapter.cursor, adapter.steps.length);
    },
  );
  test('zdbk callback to unexpected page is not success', () async {
    final auth =
        '$cas/login?service=${Uri.encodeComponent('$zdbk/xtgl/login_ssologin.html')}';
    final adapter = ScriptAdapter([
      Step('POST', '$zdbk/xtgl/login_cxSsoLoginUrl.html', '{}'),
      ...passwordLogin(auth, ticket: '$zdbk/callback'),
      Step(
        'GET',
        '$zdbk/callback',
        '',
        status: 302,
        headers: {
          'location': ['$zdbk/error.html'],
        },
      ),
    ]);
    final session = CampusSession(
      Secrets(),
      client: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(
      session.ensure('zdbk'),
      throwsA(isA<AppError>().having((e) => e.code, 'code', 'ZJU_AUTH_FAILED')),
    );
  });
  test(
    'concurrent first login shares one CAS handshake; reset discards jars',
    () async {
      final adapter = ScriptAdapter([
        ...passwordLogin('$cas/login'),
        ...passwordLogin('$cas/login'),
      ]);
      final session = CampusSession(
        Secrets(),
        client: Dio()..httpClientAdapter = adapter,
      );
      await Future.wait(List.generate(8, (_) => session.ensure('cas')));
      expect(adapter.cursor, 3);
      await session.reset();
      await session.ensure('cas');
      expect(adapter.cursor, 6);
    },
  );
  test(
    'cookie jar reproduces path defaults, one-name selection and expiry',
    () {
      final jar = LoginCookieJar(), source = Uri.parse('$cas/login');
      jar.store(source, [
        'ticket=one; Secure',
        'route=a; Path=/; Domain=.zju.edu.cn',
        'expired=x; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
      ]);
      expect(jar.header(source), 'ticket=one; route=a');
      expect(jar.header(Uri.parse('$cas/v2/getPubKey')), 'route=a');
      expect(jar.header(Uri.parse('$courses/api')), 'route=a');
      expect(
        jar.header(Uri.parse('http://zjuam.zju.edu.cn/cas/login')),
        'route=a',
      );
      jar.store(source, ['route=b; Path=/; Domain=.zju.edu.cn']);
      expect(jar.header(source), 'ticket=one; route=b');
      jar.clear();
      expect(jar.header(source), '');
    },
  );
  test(
    'ordinary binary redirect is not mistaken for authentication expiry',
    () async {
      final adapter = ScriptAdapter([
        Step('GET', '$courses/user/index', '<html>课程主页</html>'),
        Step(
          'GET',
          '$courses/blob',
          '',
          status: 302,
          headers: {
            'location': ['$courses/file.pdf'],
          },
        ),
        Step(
          'GET',
          '$courses/file.pdf',
          'PDF',
          headers: {
            'content-type': ['application/pdf'],
          },
        ),
      ]);
      final session = CampusSession(
        Secrets(),
        client: Dio()..httpClientAdapter = adapter,
      );
      expect(
        (await session.request('courses', '$courses/blob', bytes: true)).data,
        utf8.encode('PDF'),
      );
      expect(adapter.cursor, 3);
    },
  );
  test('streaming file responses write incrementally to disk', () async {
    final adapter = ScriptAdapter([
      Step('GET', '$courses/user/index', '<html>课程主页</html>'),
      Step(
        'GET',
        '$courses/blob',
        'streamed file contents',
        headers: {
          'content-type': ['application/octet-stream'],
        },
        check: (o, _) => expect(o.responseType, ResponseType.stream),
      ),
    ]);
    final session = CampusSession(
      Secrets(),
      client: Dio()..httpClientAdapter = adapter,
    );
    final directory = await Directory.systemTemp.createTemp('zju_stream_');
    final target = File(p.join(directory.path, 'file.bin'));
    try {
      final result = await session.downloadToFile(
        'courses',
        '$courses/blob',
        target,
      );
      expect(result.size, 'streamed file contents'.length);
      expect(await target.readAsString(), 'streamed file contents');
      expect(adapter.cursor, 2);
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('JSON text mentioning login is data, not an expired session', () async {
    final adapter = ScriptAdapter([
      Step('GET', '$courses/user/index', '<html>课程主页</html>'),
      Step(
        'GET',
        '$courses/api',
        '{"title":"统一身份认证的使用方法"}',
        headers: {
          'content-type': ['application/json'],
        },
      ),
    ]);
    final session = CampusSession(
      Secrets(),
      client: Dio()..httpClientAdapter = adapter,
    );
    expect(
      (await session.json('courses', '$courses/api'))['title'],
      '统一身份认证的使用方法',
    );
  });
}
