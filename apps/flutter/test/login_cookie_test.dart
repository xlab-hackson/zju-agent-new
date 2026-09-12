import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/data/login_cookie_jar.dart';

void main() {
  test('CAS hyphenated expiry and standard cookie date variants', () {
    for (final input in [
      'Thu, 01-Jan-1970 00:00:00 GMT',
      'Thu, 01 Jan 1970 00:00:00 GMT',
      'Thursday, 01-Jan-70 00:00:00 GMT',
      'Thu Jan 1 00:00:00 1970',
    ]) {
      expect(parseLoginCookieExpiry(input), DateTime.utc(1970), reason: input);
    }
    expect(
      parseLoginCookieExpiry('Wed, 09-Sep-26 15:05:04 GMT'),
      DateTime.utc(2026, 9, 9, 15, 5, 4),
    );
  });
  test(
    'past expiry deletes an existing cookie; malformed expiry never throws',
    () {
      final jar = LoginCookieJar(),
          uri = Uri.parse('https://zjuam.zju.edu.cn/cas/login');
      jar.store(uri, ['TGC=example; Path=/cas; Secure']);
      jar.store(uri, [
        'TGC=deleted; Path=/cas; Expires=Thu, 01-Jan-1970 00:00:00 GMT',
      ]);
      expect(jar.header(uri), isEmpty);
      jar.store(uri, ['session=example; Expires=invalid-date']);
      expect(jar.header(uri), 'session=example');
      for (final value in [
        'invalid-date',
        'Thu, 32 Jan 2026 00:00:00 GMT',
        'Thu, 01 Jan 2026 24:00:00 GMT',
        'Thu, 30 Feb 2026 00:00:00 GMT',
      ]) {
        expect(parseLoginCookieExpiry(value), isNull);
      }
    },
  );
}
