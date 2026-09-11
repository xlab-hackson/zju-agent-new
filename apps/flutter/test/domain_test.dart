import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/domain/models.dart';
import 'package:zju_campus_agent/domain/schedule.dart';
import 'package:zju_campus_agent/application/campus.dart';
import 'package:zju_campus_agent/application/knowledge.dart';
import 'package:zju_campus_agent/application/llm.dart';
import 'package:zju_campus_agent/data/campus_session.dart';

void main() {
  test('semester boundaries follow Beijing date', () {
    expect(academicSemester(DateTime.utc(2026, 1, 25)), '2025-2026-1');
    expect(academicSemester(DateTime.utc(2026, 1, 26)), '2025-2026-2');
    expect(academicSemester(DateTime.utc(2026, 7, 10)), '2025-2026-2');
    expect(academicSemester(DateTime.utc(2026, 7, 11)), '2026-2027-1');
    expect(
      isoDay(beijing(DateTime.parse('2026-09-09T18:00:00Z'))),
      '2026-09-10',
    );
    expect(semesterToId('2025-2026春夏'), '2025-2026-2');
    expect(semesterToId('2025-2026短'), '2025-2026-1');
  });
  test('actual session times and timetable conversion', () {
    expect(sessionTimes[6], ['13:25', '14:10']);
    expect(sessionTimes[13][1], '21:15');
    final e = parseTimetable({
      'kcb': '高等数学(A)<br>x<br>张老师<br>东1-101zwf',
      'xqj': '2',
      'djj': '6',
      'skcd': '2',
      'dsz': '0',
      'xxq': '秋',
    }, '2026-2027-1')!;
    expect(e.courseName, '高等数学（A）');
    expect(e.endSection, 7);
    expect(e.weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    expect(parseTimetable({'sfyjskc': '1'}, ''), isNull);
  });
  test('merge preserves teacher, place, semester and week distinctions', () {
    TimetableEntry entry(int start, int end, {String place = 'A'}) =>
        TimetableEntry(
          id: '$start',
          courseName: '数学',
          weekday: 1,
          startSection: start,
          endSection: end,
          location: place,
        );
    final merged = mergeTimetable([
      entry(2, 3),
      entry(1, 1),
      entry(4, 4, place: 'B'),
    ]);
    expect(merged.length, 2);
    expect(merged.first.startSection, 1);
    expect(merged.first.endSection, 3);
  });
  test('timetable course count uses distinct academic courses', () {
    TimetableEntry entry(String name, int start) => TimetableEntry(
      id: '$start',
      courseName: name,
      weekday: 1,
      startSection: start,
      endSection: start,
    );
    expect(
      timetableCourseCount([
        entry('数学', 1),
        entry('数学', 3),
        entry(' 物理 ', 5),
        entry('', 7),
      ]),
      2,
    );
  });
  test('bundled calendar holiday and makeup projection', () {
    final config = object(
      object(
        jsonDecode(File('assets/calendars.json').readAsStringSync()),
      )['2026-2027-1'],
    );
    expect(dateInfo(DateTime.utc(2026, 9, 14), config)['week'], 1);
    expect(dateInfo(DateTime.utc(2026, 10, 6), config)['effectiveWeekday'], 0);
    final makeup = dateInfo(DateTime.utc(2026, 9, 20), config);
    expect(makeup['isMakeupDay'], true);
    expect(makeup['effectiveWeekday'], 2);
    expect(makeup['makeupTargetDate'], '2026-10-06');
  });
  test('notice dates and publishers match original response fields', () {
    final sztz = parseNotices({
      'code': 0,
      'data': [
        {
          'id': 1,
          'mc': '通知',
          'fbsj': '2026-07-06T19:09:17Z',
          'zy': '<p>校园&nbsp;通知</p><br><strong>请查看</strong>',
        },
      ],
    }, 'sztz').single;
    expect(sztz['date'], '2026-07-07');
    expect(sztz['summary'], '校园 通知\n请查看');
    final zdbk = parseNotices({
      'items': [
        {'xwbh': 'a', 'xwbt': '考试', 'xwfbr': '教务处', 'fbr': '123', 'sfzd': '1'},
      ],
    }, 'zdbk').single;
    expect(zdbk['publisher'], '教务处');
    expect(zdbk['important'], true);
  });
  test('RSA protocol exponent is hexadecimal and ciphertext padded', () {
    // 65^3 mod 3233 = 3053 = 0x0bed (raw RSA, exponent 3).
    expect(encryptCampusPassword('A', '03', '0ca1'), '0bed');
    final expected = BigInt.from(65)
        .modPow(BigInt.from(65537), BigInt.from(3233))
        .toRadixString(16)
        .padLeft(4, '0');
    expect(encryptCampusPassword('A', '10001', '0ca1'), expected);
  });
  test('provider URLs preserve custom version segments', () {
    expect(
      modelEndpoint('https://api.openai.com', 'openai').path,
      '/v1/chat/completions',
    );
    expect(
      modelEndpoint('https://open.bigmodel.cn/api/paas/v4', 'openai').path,
      '/api/paas/v4/chat/completions',
    );
    expect(
      modelEndpoint('https://api.anthropic.com/v1/', 'anthropic').path,
      '/v1/messages',
    );
    expect(modelListEndpoint('https://api.openai.com').path, '/v1/models');
    expect(
      modelListEndpoint('https://open.bigmodel.cn/api/paas/v4').path,
      '/api/paas/v4/models',
    );
    expect(
      () => modelEndpoint('http://example.com', 'openai'),
      throwsA(isA<AppError>()),
    );
  });
  test('SSE parser handles arbitrary UTF8 and CRLF splits', () async {
    final data = utf8.encode(
      ': keepalive\r\ndata: {"text":"你好"}\r\n\r\ndata: [DONE]\n\n',
    );
    final events = await sseData(
      Stream.fromIterable(data.map((b) => [b])),
    ).toList();
    expect(events, ['{"text":"你好"}', '[DONE]']);
  });
  test(
    'bundled knowledge contains real searchable text and safe document paths',
    () {
      final docs = object(
        jsonDecode(File('assets/knowledge.json').readAsStringSync()),
      ).map((k, v) => MapEntry(k, '$v'));
      final index = GuideIndex(docs);
      expect(index.sections.length, greaterThan(500));
      expect(index.search('选课抽签规则'), isNotEmpty);
      expect(index.search('绩点怎么算'), isNotEmpty);
      expect(() => index.read('../credentials.enc'), throwsA(isA<AppError>()));
      expect(tokenize('选课规则'), containsAll(['选课', '课规', '规则']));
    },
  );
}
