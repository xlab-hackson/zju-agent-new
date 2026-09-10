import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import '../domain/models.dart';
import 'credentials.dart';
import 'login_cookie_jar.dart';

const campusUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0';
const _casUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0';
const _casBase = 'https://zjuam.zju.edu.cn/cas';
const _zdbkBase = 'https://zdbk.zju.edu.cn/jwglxt';

/// login-zju RSA.ts iterates JS code points and then takes charCodeAt(0).
/// This is raw modular RSA, not PKCS#1 encryption or UTF-8 encoding.
String encryptCampusPassword(String password, String exponent, String modulus) {
  var value = BigInt.zero;
  for (final rune in password.runes) {
    final code = rune > 0xffff ? ((rune - 0x10000) >> 10) + 0xd800 : rune;
    value = value * BigInt.from(256) + BigInt.from(code);
  }
  return value
      .modPow(
        BigInt.parse(exponent, radix: 16),
        BigInt.parse(modulus, radix: 16),
      )
      .toRadixString(16)
      .padLeft(modulus.length, '0');
}

class _LoginState {
  final jars = {
    for (final name in ['cas', 'courses', 'zdbk']) name: LoginCookieJar(),
  };
  final ready = <String>{};
  final revisions = <String, int>{};
  final flights = <String, Future<void>>{};
  final downloadTokens = <CancelToken>{};
  final cancellation = CancelToken();
  Future<void> queue = Future.value();
  bool casLoggedIn = false;
}

/// Ports ZJUAM, COURSES, ZDBK from login-zju 1.0.9. Each owns its jar;
/// only the ZJUAM instance is shared. No cookie or redirect URL is logged.
class CampusSession {
  CampusSession(this.secrets, {Dio? client})
    : dio =
          client ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
  final SecretStore secrets;
  final Dio dio;
  _LoginState _state = _LoginState();
  String _authStatus = 'unknown';

  /// The last known state of an authenticated campus request. Credentials
  /// being present locally is not enough to call the session connected.
  String get authStatus => _authStatus;

  Future<void> reset() async {
    final old = _state;
    _state = _LoginState();
    _authStatus = 'unknown';
    old.cancellation.cancel();
    for (final token in old.downloadTokens) {
      token.cancel('登录已取消');
    }
    for (final jar in old.jars.values) {
      jar.clear();
    }
  }

  void _check(_LoginState state) {
    if (!identical(state, _state) || state.cancellation.isCancelled) {
      throw const AppError('CANCELLED', '登录已取消，请重新操作。');
    }
  }

  /// Redirects are manual here so Set-Cookie is saved before the next hop.
  /// Login requests carry the upstream UA only; AJAX headers belong to API calls.
  Future<Response<dynamic>> _fetch(
    _LoginState state,
    String owner,
    String url, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic> headers = const {},
    bool follow = false,
    bool bytes = false,
    bool stream = false,
    CancelToken? cancelToken,
  }) async {
    final jar = state.jars[owner]!;
    var current = Uri.parse(url), verb = method, body = data;
    var requestHeaders = <String, dynamic>{
      'User-Agent': campusUserAgent,
      ...headers,
    };
    for (var hop = 0; hop < 20; hop++) {
      _check(state);
      if (current.scheme != 'https' ||
          current.userInfo.isNotEmpty ||
          !(current.host == 'zju.edu.cn' ||
              current.host.endsWith('.zju.edu.cn'))) {
        throw const AppError('ZJU_AUTH_FAILED', '校园服务返回了不受支持的跳转地址。');
      }
      Response<dynamic> response;
      try {
        response = await dio.request<dynamic>(
          current.toString(),
          data: body,
          cancelToken: cancelToken ?? state.cancellation,
          options: Options(
            method: verb,
            followRedirects: false,
            validateStatus: (s) => s != null,
            responseType: stream
                ? ResponseType.stream
                : bytes
                ? ResponseType.bytes
                : ResponseType.plain,
            headers: {...requestHeaders, 'Cookie': jar.header(current)},
          ),
        );
      } on DioException catch (e) {
        if (cancelToken?.isCancelled == true) {
          throw const AppError('CANCELLED', '下载已取消。');
        }
        _check(state);
        throw AppError(
          'ZJU_SERVICE_UNAVAILABLE',
          '校园网络请求失败（${e.type.name}），请检查网络后重试。',
          retryable: true,
        );
      }
      if (cancelToken?.isCancelled == true) {
        throw const AppError('CANCELLED', '下载已取消。');
      }
      _check(state);
      jar.store(current, response.headers['set-cookie'] ?? []);
      if (!follow || !_isRedirect(response.statusCode)) return response;
      final location = _location(response, current.toString());
      final next = Uri.parse(location);
      if (current.origin != next.origin) {
        requestHeaders.removeWhere(
          (k, _) =>
              ['authorization', 'cookie', 'referer'].contains(k.toLowerCase()),
        );
      }
      // Fetch semantics: 301/302 POST and 303 non-HEAD switch to GET.
      if (((response.statusCode == 301 || response.statusCode == 302) &&
              verb == 'POST') ||
          (response.statusCode == 303 && verb != 'HEAD')) {
        verb = 'GET';
        body = null;
        requestHeaders.removeWhere((k, _) => k.toLowerCase() == 'content-type');
      }
      current = next;
    }
    throw const AppError('ZJU_AUTH_FAILED', '校园服务跳转次数过多。');
  }

  static bool _isRedirect(int? status) =>
      [301, 302, 303, 307, 308].contains(status);
  String _location(Response<dynamic> r, String current) {
    final location = r.headers.value('location');
    if (location == null || location.trim().isEmpty) {
      throw const AppError('ZJU_AUTH_FAILED', '校园登录响应缺少跳转地址。');
    }
    return Uri.parse(current).resolve(location).toString();
  }

  String _body(Response<dynamic> response) => response.data is List<int>
      ? utf8.decode(response.data as List<int>, allowMalformed: true)
      : '${response.data ?? ''}';

  Future<void> _closeResponse(Response<dynamic> response) async {
    final body = response.data;
    if (body is ResponseBody) {
      final subscription = body.stream.listen((_) {});
      await subscription.cancel();
    }
  }

  Future<String> _passwordLogin(_LoginState state, String loginUrl) async {
    final credential = await secrets.read('campus');
    _check(state);
    if (credential == null ||
        text(credential, 'username').isEmpty ||
        text(credential, 'password').isEmpty) {
      throw const AppError('ZJU_CREDENTIAL_MISSING', '请先在设置中配置浙大账号。');
    }
    final page = await _fetch(state, 'cas', loginUrl, follow: true);
    final execution = html
        .parse(_body(page))
        .querySelector('input[name="execution"]')
        ?.attributes['value'];
    if (execution == null || execution.isEmpty) {
      throw const AppError('ZJU_AUTH_FAILED', '统一认证登录页缺少 execution 参数。');
    }
    final pubResponse = await _fetch(
      state,
      'cas',
      '$_casBase/v2/getPubKey',
      follow: true,
    );
    String encrypted;
    try {
      final pub = object(jsonDecode(_body(pubResponse)));
      encrypted = encryptCampusPassword(
        text(credential, 'password'),
        text(pub, 'exponent'),
        text(pub, 'modulus'),
      );
    } catch (_) {
      throw const AppError('ZJU_RESPONSE_PARSE_FAILED', '统一认证公钥响应无效。');
    }
    // Keep field order and application/x-www-form-urlencoded wire format.
    final body = [
      'username=${Uri.encodeQueryComponent(text(credential, 'username'))}',
      'password=$encrypted',
      'execution=${Uri.encodeQueryComponent(execution)}',
      '_eventId=submit',
      'authcode=',
    ].join('&');
    final response = await _fetch(
      state,
      'cas',
      loginUrl,
      method: 'POST',
      data: body,
      headers: {
        'Content-Type': Headers.formUrlEncodedContentType,
        'User-Agent': _casUserAgent,
      },
    );
    if (response.statusCode != 302) {
      final message = html
          .parse(_body(response))
          .querySelector('#msg')
          ?.text
          .trim();
      final safe = (message ?? '')
          .replaceAll(text(credential, 'password'), '[已隐藏]')
          .replaceAll(text(credential, 'username'), '[已隐藏]');
      throw AppError(
        'ZJU_AUTH_FAILED',
        safe.isEmpty
            ? '统一认证登录失败（HTTP ${response.statusCode}），请检查账号密码。'
            : '统一认证登录失败：${safe.length > 180 ? safe.substring(0, 180) : safe}',
      );
    }
    final callback = _location(response, loginUrl);
    state.casLoggedIn = true;
    return callback;
  }

  /// ZJUAM.loginSvc: existing session -> manual GET -> 302 callback;
  /// HTTP 200 -> fresh login-page GET + public-key GET + credential POST.
  Future<String> _loginSvc(_LoginState state, String service) async {
    final loginUrl = '$_casBase/login?service=${Uri.encodeComponent(service)}';
    if (state.casLoggedIn) {
      final response = await _fetch(
        state,
        'cas',
        loginUrl,
        headers: {'User-Agent': _casUserAgent},
      );
      if (response.statusCode == 302) return _location(response, loginUrl);
      if (response.statusCode != 200) {
        throw AppError(
          'ZJU_AUTH_FAILED',
          'CAS 服务认证失败（HTTP ${response.statusCode}）。',
        );
      }
    }
    return _passwordLogin(state, loginUrl);
  }

  Future<void> _loginCourses(_LoginState state) async {
    var url = 'https://courses.zju.edu.cn/user/index';
    var reachedCas = false;
    for (var i = 0; i < 20; i++) {
      if (Uri.parse(url).host == 'zjuam.zju.edu.cn') {
        reachedCas = true;
        break;
      }
      final response = await _fetch(state, 'courses', url);
      // An already valid service session needs no new ticket.
      if (response.statusCode == 200 && !_looksLikeLogin(response)) return;
      url = _location(response, url);
    }
    if (!reachedCas) throw const AppError('ZJU_AUTH_FAILED', '学在浙大未能跳转到统一认证。');
    final service = Uri.parse(url).queryParameters['service'];
    if (service == null || service.isEmpty) {
      throw const AppError('ZJU_AUTH_FAILED', '学在浙大认证地址缺少 service 参数。');
    }
    url = await _loginSvc(state, service);
    for (var i = 0; i < 20; i++) {
      final response = await _fetch(state, 'courses', url);
      if (response.statusCode == 200) {
        String? refresh;
        for (final meta
            in html.parse(_body(response)).querySelectorAll('meta')) {
          if (meta.attributes['http-equiv']?.toLowerCase() == 'refresh') {
            refresh = RegExp(
              r'url\s*=\s*(.+)',
              caseSensitive: false,
            ).firstMatch(meta.attributes['content'] ?? '')?[1];
          }
        }
        if (refresh != null) {
          url = Uri.parse(url).resolve(refresh).toString();
          continue;
        }
        if (!_looksLikeLogin(response)) return;
      }
      if (_isRedirect(response.statusCode)) {
        url = _location(response, url);
        continue;
      }
      throw const AppError('ZJU_AUTH_FAILED', '学在浙大回调未建立有效登录会话。');
    }
    throw const AppError('ZJU_AUTH_FAILED', '学在浙大登录跳转次数过多。');
  }

  Future<void> _loginZdbk(_LoginState state) async {
    await _fetch(
      state,
      'zdbk',
      '$_zdbkBase/xtgl/login_cxSsoLoginUrl.html',
      method: 'POST',
      follow: true,
    );
    final callback = await _loginSvc(
      state,
      '$_zdbkBase/xtgl/login_ssologin.html',
    );
    final response = await _fetch(state, 'zdbk', callback);
    if (response.statusCode != 302 ||
        !_location(
          response,
          callback,
        ).startsWith('$_zdbkBase/xtgl/index_initMenu.html')) {
      throw const AppError('ZJU_AUTH_FAILED', '教务网登录回调未跳转到主页。');
    }
    // Upstream stops here: the menu is not fetched and is not parsed for auth keywords.
  }

  Future<void> ensure(String service) => _ensure(_state, service);
  Future<void> _ensure(_LoginState state, String service) {
    _check(state);
    if (!state.jars.containsKey(service)) {
      throw const AppError('INVALID_INPUT', '不支持的校园服务。');
    }
    if (state.ready.contains(service)) return Future.value();
    final pending = state.flights[service];
    if (pending != null) return pending;
    final work = state.queue.then((_) async {
      _check(state);
      if (state.ready.contains(service)) return;
      switch (service) {
        case 'cas':
          await _passwordLogin(state, '$_casBase/login');
        case 'courses':
          await _loginCourses(state);
        case 'zdbk':
          await _loginZdbk(state);
      }
      _check(state);
      state.ready.add(service);
      state.revisions[service] = (state.revisions[service] ?? 0) + 1;
    });
    final flight = work.whenComplete(() {
      state.flights.remove(service);
    });
    state.flights[service] = flight;
    state.queue = flight.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return flight;
  }

  bool _looksLikeLogin(Response<dynamic> response) {
    final body = _body(response).trimLeft();
    final contentType = response.headers.value('content-type') ?? '';
    if (!contentType.contains('text/html') && !body.startsWith('<')) {
      return false;
    }
    return RegExp(
      r'统一身份认证|login_ssologin|cas/login|name=["\x27]execution|未登录',
    ).hasMatch(body);
  }

  bool _expired(Response<dynamic> response) {
    if ([401, 403, 901].contains(response.statusCode)) return true;
    if (_isRedirect(response.statusCode)) {
      final location = response.headers.value('location') ?? '';
      return RegExp(
        r'zjuam\.zju\.edu\.cn|login_ssologin|/cas/login|/user/login',
      ).hasMatch(location);
    }
    return _looksLikeLogin(response);
  }

  Future<Response<dynamic>> request(
    String service,
    String url, {
    String method = 'GET',
    Object? data,
    bool bytes = false,
    bool stream = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _request(
        service,
        url,
        method: method,
        data: data,
        bytes: bytes,
        stream: stream,
        cancelToken: cancelToken,
      );
      _authStatus = 'connected';
      return response;
    } on AppError catch (e) {
      if (e.code == 'ZJU_AUTH_FAILED' || e.code == 'ZJU_CREDENTIAL_MISSING') {
        _authStatus = 'invalid';
      }
      rethrow;
    }
  }

  Future<Response<dynamic>> _request(
    String service,
    String url, {
    String method = 'GET',
    Object? data,
    bool bytes = false,
    bool stream = false,
    CancelToken? cancelToken,
  }) async {
    final state = _state;
    if (cancelToken?.isCancelled == true) {
      throw const AppError('CANCELLED', '下载已取消。');
    }
    Future<void> ensureService() {
      final ensure = _ensure(state, service);
      if (cancelToken == null) return ensure;
      return Future.any<void>([
        ensure,
        cancelToken.whenCancel.then<void>(
          (_) => throw const AppError('CANCELLED', '下载已取消。'),
        ),
      ]);
    }

    await ensureService();
    _check(state);
    if (cancelToken?.isCancelled == true) {
      throw const AppError('CANCELLED', '下载已取消。');
    }
    final revision = state.revisions[service];
    final headers = <String, dynamic>{
      if (service == 'zdbk') ...{
        'Referer': '$_zdbkBase/xtgl/index_initMenu.html',
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
      },
      if (data != null) 'Content-Type': Headers.formUrlEncodedContentType,
    };
    Future<Response<dynamic>> fetch() async {
      var current = url;
      for (var i = 0; i < 20; i++) {
        final r = await _fetch(
          state,
          service,
          current,
          method: i == 0 ? method : 'GET',
          data: i == 0 ? data : null,
          headers: headers,
          bytes: bytes,
          stream: stream,
          cancelToken: cancelToken,
        );
        if (_expired(r) || !_isRedirect(r.statusCode)) return r;
        await _closeResponse(r);
        current = _location(r, current);
      }
      throw const AppError('ZJU_SERVICE_UNAVAILABLE', '校园请求跳转次数过多。');
    }

    var response = await fetch();
    if (_expired(response)) {
      await _closeResponse(response);
      if (state.revisions[service] == revision) state.ready.remove(service);
      await ensureService();
      response = await fetch();
    }
    _check(state);
    if (_expired(response)) {
      throw const AppError('ZJU_AUTH_FAILED', '登录已过期，请重新登录。');
    }
    if (stream &&
        (response.headers.value(Headers.contentTypeHeader) ?? '')
            .toLowerCase()
            .contains('text/html')) {
      await _closeResponse(response);
      throw const AppError('ZJU_AUTH_FAILED', '校园服务返回了登录页面，请重新登录后重试。');
    }
    if ((response.statusCode ?? 500) >= 400) {
      throw AppError(
        'ZJU_SERVICE_UNAVAILABLE',
        '校园服务返回 HTTP ${response.statusCode}。',
        retryable: true,
      );
    }
    return response;
  }

  /// Stream a response directly to [target]. Unlike ResponseType.bytes this
  /// keeps only one network chunk in memory and applies backpressure while
  /// the file is written, so a large download cannot retain a whole duplicate
  /// byte array on the UI isolate.
  Future<CampusFileDownload> downloadToFile(
    String service,
    String url,
    File target, {
    CancelToken? cancelToken,
    int maxBytes = 512 * 1024 * 1024,
  }) async {
    final state = _state;
    if (cancelToken != null) {
      state.downloadTokens.add(cancelToken);
      if (state.cancellation.isCancelled) cancelToken.cancel('登录已取消');
    }
    try {
      final response = await request(
        service,
        url,
        stream: true,
        cancelToken: cancelToken,
      );
      final contentType =
          response.headers.value(Headers.contentTypeHeader)?.toLowerCase() ??
          '';
      if (contentType.contains('text/html')) {
        await _closeResponse(response);
        throw const AppError('ZJU_AUTH_FAILED', '校园服务返回了登录页面，请重新登录后重试。');
      }
      final declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declaredLength != null && declaredLength > maxBytes) {
        await _closeResponse(response);
        throw const AppError('FILE_DOWNLOAD_FAILED', '文件超过 512 MB，请使用学校页面下载。');
      }
      final body = response.data;
      if (body is! ResponseBody) {
        throw const AppError('FILE_DOWNLOAD_FAILED', '校园服务未返回可下载的文件流。');
      }

      await target.parent.create(recursive: true);
      final iterator = StreamIterator<Uint8List>(body.stream);
      RandomAccessFile? file;
      var received = 0;
      try {
        file = await target.open(mode: FileMode.write);
        while (true) {
          if (cancelToken?.isCancelled == true) {
            throw const AppError('CANCELLED', '下载已取消。');
          }
          final moveNext = iterator.moveNext();
          final hasNext = cancelToken == null
              ? await moveNext
              : await Future.any<bool>([
                  moveNext,
                  cancelToken.whenCancel.then<bool>((_) => false),
                ]);
          if (!hasNext) {
            if (cancelToken?.isCancelled == true) {
              throw const AppError('CANCELLED', '下载已取消。');
            }
            break;
          }
          final chunk = iterator.current;
          final next = received + chunk.length;
          if (next > maxBytes) {
            throw const AppError(
              'FILE_DOWNLOAD_FAILED',
              '文件超过 512 MB，请使用学校页面下载。',
            );
          }
          await file.writeFrom(chunk);
          received = next;
          _check(state);
        }
        return CampusFileDownload(
          size: received,
          mimeType: response.headers.value(Headers.contentTypeHeader),
        );
      } finally {
        await iterator.cancel();
        await file?.close();
      }
    } finally {
      if (cancelToken != null) state.downloadTokens.remove(cancelToken);
    }
  }

  Future<Json> json(
    String service,
    String url, {
    String method = 'GET',
    Object? data,
    CancelToken? cancelToken,
  }) async {
    final response = await request(
      service,
      url,
      method: method,
      data: data,
      cancelToken: cancelToken,
    );
    try {
      return object(
        response.data is String ? jsonDecode(response.data) : response.data,
      );
    } on FormatException {
      throw const AppError('ZJU_RESPONSE_PARSE_FAILED', '校园接口返回了无法解析的数据。');
    }
  }
}

class CampusFileDownload {
  const CampusFileDownload({required this.size, required this.mimeType});
  final int size;
  final String? mimeType;
}
