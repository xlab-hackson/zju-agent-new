import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import '../data/campus_session.dart';
import '../data/database.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';

class CampusService {
  CampusService(this.session, this.db);
  final CampusSession session;
  final AgentDatabase db;
  final Dio publicClient = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': campusUserAgent},
    ),
  );
  static const coursesBase = 'https://courses.zju.edu.cn';
  static const zdbkBase = 'https://zdbk.zju.edu.cn/jwglxt';
  static const cacheValidity = Duration(days: 1);
  final Set<String> stale = {};

  DateTime? _cacheTime(Json? value) {
    if (value == null) return null;
    return DateTime.tryParse(text(value, 'updatedAt'))?.toUtc();
  }

  bool _isFresh(DateTime? time) =>
      time != null && DateTime.now().toUtc().difference(time) < cacheValidity;

  Future<DateTime?> oldestUpdatedAt({
    Iterable<String> cacheKeys = const [],
    Iterable<String> cachePrefixes = const [],
    Iterable<String> calendarKeys = const [],
  }) async {
    final times = <DateTime>[];
    for (final key in cacheKeys) {
      final time = _cacheTime(await db.get('cache', key));
      if (time != null) times.add(time);
    }
    for (final prefix in cachePrefixes) {
      for (final key in await db.ids('cache', prefix: prefix)) {
        final time = _cacheTime(await db.get('cache', key));
        if (time != null) times.add(time);
      }
    }
    for (final key in calendarKeys) {
      final time = await db.updatedAt('calendars', key);
      if (time != null) times.add(time);
    }
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Future<List<Json>> cached(
    String key,
    Future<List<Json>> Function() fetch, {
    bool refresh = false,
  }) async {
    final cache = await db.get('cache', key);
    if (!refresh && _isFresh(_cacheTime(cache))) {
      stale.remove(key);
      return rows(cache!['items']);
    }
    try {
      final items = await fetch();
      stale.remove(key);
      await db.put('cache', key, {
        'items': items,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      return items;
    } on AppError catch (e) {
      if (cache == null ||
          e.code == 'ZJU_AUTH_FAILED' ||
          e.code == 'ZJU_CREDENTIAL_MISSING') {
        rethrow;
      }
      stale.add(key);
      return rows(cache['items']);
    }
  }

  Future<List<Json>> semesters({bool refresh = false}) =>
      cached('semesters', () async {
        final json = await session.json(
          'courses',
          '$coursesBase/api/my-semesters?',
        );
        return rows(json['semesters'])
            .map(
              (s) => {
                'id': '${s['id']}',
                'name': s['name'],
                'isActive': s['is_active'] == true,
              },
            )
            .toList();
      }, refresh: refresh);
  Future<List<Json>> courses({String? semesterId, bool refresh = false}) async {
    final all = await cached('courses', () async {
      final url = Uri.parse('$coursesBase/api/my-courses').replace(
        queryParameters: {
          'conditions': jsonEncode({
            'status': ['ongoing', 'notStarted', 'ended'],
            'keyword': '',
            'classify_type': 'recently_started',
            'display_studio_list': false,
          }),
          'fields': 'id,name,semester_id,course_attributes',
          'page': '1',
          'page_size': '1000',
        },
      );
      final j = await session.json('courses', url.toString());
      return rows(j['courses'])
          .map(
            (c) => {
              'id': '${c['id']}',
              'name': c['name'],
              'semesterId': '${c['semester_id']}',
              'teachingClassName':
                  (c['course_attributes'] as Map?)?['teaching_class_name'],
            },
          )
          .toList();
    }, refresh: refresh);
    if (semesterId == null) return all;
    final ids = (await semesters(refresh: refresh))
        .where(
          (s) =>
              s['id'] == semesterId ||
              semesterToId(text(s, 'name')) == semesterId,
        )
        .map((s) => s['id'])
        .toSet();
    return all.where((c) => ids.contains(c['semesterId'])).toList();
  }

  /// Read a course name without starting a network request. Downloads should
  /// never wait for a second campus request just to choose a folder name.
  Future<String> cachedCourseName(String courseId) async {
    try {
      final cache = await db.get('cache', 'courses');
      if (cache == null) return '';
      for (final course in rows(cache['items'])) {
        if (text(course, 'id') == courseId) return text(course, 'name').trim();
      }
    } catch (_) {
      // Fall back to the deterministic course-ID folder.
    }
    return '';
  }

  Future<List<Json>> materials(
    String courseId, {
    bool refresh = false,
  }) => cached('materials:$courseId', () async {
    final url =
        Uri.parse(
          '$coursesBase/api/course/${Uri.encodeComponent(courseId)}/coursewares',
        ).replace(
          queryParameters: {
            'conditions': jsonEncode({
              'category': null,
              'itemsSortBy': {'predicate': 'chapter', 'reverse': false},
              'ignore_activity_types': ['lesson'],
            }),
            'page': '1',
            'page_size': '1000',
          },
        );
    final j = await session.json('courses', url.toString());
    return rows(j['activities'])
        .map(
          (a) => {
            'id': '${a['id']}',
            'courseId': courseId,
            'title': a['title'],
            'files': rows(a['uploads'] ?? [])
                .map(
                  (u) => {
                    'id': '${u['id']}',
                    'referenceId': '${u['reference_id']}',
                    'name': text(u, 'name').trim(),
                  },
                )
                .toList(),
          },
        )
        .toList();
  }, refresh: refresh);
  Future<List<Json>> assignments({
    String? courseId,
    String? semesterId,
    bool refresh = false,
  }) async {
    final selected = (await courses(
      semesterId: semesterId,
      refresh: refresh,
    )).where((c) => courseId == null || c['id'] == courseId);
    final result = <Json>[];
    for (final c in selected) {
      result.addAll(
        await cached('assignments:${c['id']}', () async {
          final j = await session.json(
            'courses',
            '$coursesBase/api/courses/${Uri.encodeComponent('${c['id']}')}/homework-activities?page=1&page_size=1000',
          );
          return rows(j['homework_activities'])
              .map(
                (a) => {
                  'id': '${a['id']}',
                  'courseId': c['id'],
                  'courseName': c['name'],
                  'title': a['title'],
                  'deadline': a['deadline'],
                  'submitted': a['submitted'] == true,
                  'isClosed': a['is_closed'] == true,
                  'description': (a['data'] as Map?)?['description'],
                  'attachments': rows(a['uploads'] ?? [])
                      .map((u) => {'id': '${u['id']}', 'name': u['name']})
                      .toList(),
                },
              )
              .toList();
        }, refresh: refresh),
      );
    }
    return result;
  }

  Future<List<Json>> quizzes(
    String courseId, {
    bool refresh = false,
  }) => cached('quizzes:$courseId', () async {
    final j = await session.json(
      'courses',
      '$coursesBase/api/courses/${Uri.encodeComponent(courseId)}/exam-list?page=1&page_size=100',
    );
    return rows(j['exams'])
        .where((e) => e['is_closed'] != true)
        .map(
          (e) => {
            'id': '${e['id']}',
            'courseId': courseId,
            'title': e['title'],
            'deadline': e['end_time'],
            'submitted': integer(e['submission_count']) > 0,
            'url':
                '$coursesBase/course/$courseId/learning-activity#/exam/${e['id']}',
          },
        )
        .toList();
  }, refresh: refresh);
  Future<List<TimetableEntry>> timetable(
    String semester, {
    bool refresh = false,
  }) async => (await cached('timetable:$semester', () async {
    if (!RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(semester)) {
      throw const AppError('INVALID_INPUT', '学期格式不正确。');
    }
    final entries = <TimetableEntry>[];
    for (final sub in semester.endsWith('-1') ? ['秋', '冬'] : ['春', '夏']) {
      final j = await session.json(
        'zdbk',
        '$zdbkBase/kbcx/xskbcx_cxXsKb.html',
        method: 'POST',
        data: {
          'xnm': semester.substring(0, 9),
          'xqm': '${semester.substring(10)}|$sub',
          'captcha_value': '',
        },
      );
      for (final row in rows(j['kbList'])) {
        final e = parseTimetable(row, semester);
        if (e != null) entries.add(e);
      }
    }
    return mergeTimetable(entries).map((e) => e.toJson()).toList();
  }, refresh: refresh)).map(TimetableEntry.fromJson).toList();
  Future<List<Json>> exams(
    String semester, {
    bool refresh = false,
  }) => cached('exams:$semester', () async {
    final credential = await session.secrets.read('campus');
    final j = await session.json(
      'zdbk',
      '$zdbkBase/xskscx/kscx_cxXsgrksIndex.html?doType=query&gnmkdm=N509070&layout=default&su=${Uri.encodeComponent(text(credential ?? {}, 'username'))}',
      method: 'POST',
      data: {
        '_search': 'false',
        'queryModel.showCount': '5000',
        'queryModel.currentPage': '1',
        'queryModel.sortName': 'xkkh',
        'queryModel.sortOrder': 'desc',
        'time': '0',
      },
    );
    final result = <Json>[];
    for (final e in rows(
      j['items'],
    ).where((r) => text(r, 'xkkh').contains(semester))) {
      for (final prefix in ['', 'qz']) {
        if (text(e, '${prefix}kssj').isEmpty) continue;
        result.add({
          'id': '$semester-${e['kcmc']}-$prefix',
          'courseName': e['kcmc'],
          'time': parseExamTime(text(e, '${prefix}kssj')),
          'location': e['${prefix}jsmc'],
          'seat': e['${prefix}zwxh'],
          'semester': semester,
        });
      }
    }
    return result..sort((a, b) => text(a, 'time').compareTo(text(b, 'time')));
  }, refresh: refresh);
  Future<List<Json>> grades(
    String semester, {
    bool refresh = false,
  }) => cached('grades:$semester', () async {
    final j = await session.json(
      'zdbk',
      '$zdbkBase/cxdy/xscjcx_cxXscjIndex.html?doType=query&queryModel.showCount=5000',
      method: 'POST',
    );
    return rows(
      j['items'],
    ).where((r) => semester.isEmpty || text(r, 'xkkh').contains(semester)).map((
      r,
    ) {
      final grade = text(r, 'CJ', text(r, 'cj')),
          id = text(r, 'KCH', text(r, 'xkkh'));
      final included =
          !['弃修', '待录', '缓考', '无效'].contains(grade) &&
          text(r, 'BZ', text(r, 'bz')) != '弃修';
      return {
        'id': id,
        'courseName': r['KCMC'] ?? r['kcmc'],
        'original': grade,
        'credit': r['XF'] ?? r['xf'],
        'fivePoint': r['JD'] ?? r['jd'],
        'semester': semester,
        'creditIncluded': included,
        'gpaIncluded':
            included && !['合格', '不合格'].contains(grade) && !id.contains('xtwkc'),
      };
    }).toList();
  }, refresh: refresh);
  Future<Json> notices({bool refresh = false}) async {
    final items = <Json>[], failures = <String>[];
    for (final source in ['sztz', 'zdbk']) {
      final key = 'notices:$source', saved = await db.get('cache', key);
      final savedAt = _cacheTime(saved);
      if (!refresh && _isFresh(savedAt)) {
        stale.remove(key);
        items.addAll(rows(saved?['items']));
        continue;
      }
      try {
        final r = source == 'sztz'
            ? await publicClient.get<dynamic>(
                'https://sztz.zju.edu.cn/dekt/student/home/getTzggList?page=1&limit=30',
              )
            : await publicClient.post<dynamic>(
                '$zdbkBase/xtgl/xwck_cxMoreLoginNews.html?doType=query',
                data: {
                  'xwbt': '',
                  'queryModel.showCount': '30',
                  'queryModel.currentPage': '1',
                  'queryModel.sortName': 'sfzd desc, fbsj',
                  'queryModel.sortOrder': 'desc',
                  'time': '0',
                },
                options: Options(
                  contentType: Headers.formUrlEncodedContentType,
                  headers: {'X-Requested-With': 'XMLHttpRequest'},
                ),
              );
        final j = object(r.data is String ? jsonDecode(r.data) : r.data);
        final parsed = parseNotices(j, source);
        items.addAll(parsed);
        await db.put('cache', key, {
          'items': parsed,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
        stale.remove(key);
      } catch (_) {
        stale.add(key);
        failures.add('${source == 'sztz' ? '素质拓展' : '教务'}通知刷新失败');
        if (saved != null) items.addAll(rows(saved['items']));
      }
    }
    items.sort(
      (a, b) =>
          (b['important'] == true ? 1 : 0).compareTo(
                a['important'] == true ? 1 : 0,
              ) !=
              0
          ? (b['important'] == true ? 1 : 0).compareTo(
              a['important'] == true ? 1 : 0,
            )
          : text(b, 'date').compareTo(text(a, 'date')),
    );
    final updated = <DateTime>[];
    for (final source in ['sztz', 'zdbk']) {
      final time = _cacheTime(await db.get('cache', 'notices:$source'));
      if (time != null) updated.add(time);
    }
    return {
      'items': items,
      'failures': failures,
      if (updated.isNotEmpty)
        'updatedAt': updated
            .reduce((a, b) => a.isBefore(b) ? a : b)
            .toIso8601String(),
    };
  }

  Future<Json> calendar(String semester, {bool refresh = false}) async {
    final saved = await db.get('calendars', semester);
    final savedAt = await db.updatedAt('calendars', semester);
    if (!refresh && saved != null && _isFresh(savedAt)) return saved;
    try {
      final r = await publicClient.get<dynamic>(
        'http://calendar.celechron.top/${Uri.encodeComponent(semester)}.json',
        options: Options(receiveTimeout: const Duration(seconds: 2)),
      );
      final j = object(r.data is String ? jsonDecode(r.data) : r.data);
      if (j['startEnd'] is List && (j['startEnd'] as List).length == 4) {
        final config = {
          ...j,
          'semesterId': semester,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
        await db.put('calendars', semester, config);
        stale.remove('calendar:$semester');
        return config;
      }
    } catch (_) {
      /* Bundled calendar is available offline. */
    }
    if (saved != null) {
      stale.add('calendar:$semester');
      return saved;
    }
    final bundled = object(
      jsonDecode(await rootBundle.loadString('assets/calendars.json')),
    );
    if (bundled[semester] != null) return object(bundled[semester]);
    throw const AppError('ZJU_SERVICE_UNAVAILABLE', '该学期校历尚未收录，无法准确计算日程。');
  }

  Future<Json> daily(DateTime wall, {bool refresh = false}) async {
    final semester = academicSemester(wall),
        config = await calendar(semester, refresh: refresh);
    final table = await timetable(semester, refresh: refresh),
        tests = await exams(semester, refresh: refresh),
        work = await assignments(semesterId: semester, refresh: refresh);
    return {
      'date': isoDay(wall),
      'dateInfo': dateInfo(wall, config),
      'events': dailyEvents(wall, config, table, tests, work),
    };
  }

  Future<Json> upcoming({DateTime? now, bool refresh = false}) async {
    final wall = beijing(now ?? DateTime.now()),
        end = beijing(now ?? DateTime.now()).add(const Duration(hours: 48));
    final all = <Json>[];
    Json? firstDateInfo;
    final calendars = <String, Json>{};
    final timetables = <String, List<TimetableEntry>>{};
    final examsBySemester = <String, List<Json>>{};
    final assignmentsBySemester = <String, List<Json>>{};
    for (var i = 0; i < 3; i++) {
      final current = day(wall).add(Duration(days: i)),
          semester = academicSemester(current),
          config = calendars[semester] ??= await calendar(
            semester,
            refresh: refresh,
          ),
          table = timetables[semester] ??= await timetable(
            semester,
            refresh: refresh,
          ),
          tests = examsBySemester[semester] ??= await exams(
            semester,
            refresh: refresh,
          ),
          work = assignmentsBySemester[semester] ??= await assignments(
            semesterId: semester,
            refresh: refresh,
          );
      final info = dateInfo(current, config);
      firstDateInfo ??= info;
      all.addAll(dailyEvents(current, config, table, tests, work));
    }
    final events = all.where((e) {
      final start = DateTime.parse('${e['date']}T${e['startTime']}:00Z'),
          finish = DateTime.parse('${e['date']}T${e['endTime']}:00Z');
      return !finish.isBefore(wall) && !start.isAfter(end);
    }).toList();
    return {
      'now': wall.toIso8601String(),
      'dateInfo': firstDateInfo ?? {},
      'events': events,
      'assignments48h': events.where((e) => e['type'] == 'assignment').toList(),
    };
  }
}

TimetableEntry? parseTimetable(Json r, String semester) {
  if (text(r, 'sfyjskc') == '1') return null;
  final m = RegExp(
    r'(.*?)<br>(.*?)<br>(.*?)<br>(.*?)zwf',
  ).firstMatch(text(r, 'kcb'));
  if (m == null) return null;
  final start = integer(r['djj']), weekday = integer(r['xqj']);
  if (start < 1 || weekday < 1 || weekday > 7) return null;
  final parity = text(r, 'dsz');
  return TimetableEntry(
    id: '${m[1]}-$weekday-$start',
    courseName: m[1]!.trim().replaceAll('(', '（').replaceAll(')', '）'),
    weekday: weekday,
    startSection: start,
    endSection: start + integer(r['skcd'], 1) - 1,
    teacher: m[3]!.trim(),
    location: m[4]!.trim(),
    semester: semester,
    subSemester: text(r, 'xxq'),
    weeks: parity == '0'
        ? [1, 3, 5, 7, 9, 11, 13, 15]
        : parity == '1'
        ? [2, 4, 6, 8, 10, 12, 14, 16]
        : [],
  );
}

String parseExamTime(String raw) {
  final m = RegExp(
    r'^(\d{4})年(\d{2})月(\d{2})日\((\d{2}):(\d{2})',
  ).firstMatch(raw);
  return m == null ? raw : '${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:00+08:00';
}

List<Json> parseNotices(Json j, String source) {
  if (source == 'sztz' && integer(j['code'], -1) != 0) {
    throw const AppError('ZJU_RESPONSE_PARSE_FAILED', '通知接口返回错误。');
  }
  final list = rows(source == 'sztz' ? j['data'] : j['items']);
  return list.map((r) {
    final id = text(r, source == 'sztz' ? 'id' : 'xwbh'),
        date = text(r, 'fbsj');
    final parsed = DateTime.tryParse(date);
    return {
      'id': '$source:$id',
      'title': r[source == 'sztz' ? 'mc' : 'xwbt'],
      'source': source,
      'date': source == 'sztz' && parsed != null
          ? isoDay(beijing(parsed))
          : date,
      'publisher': r[source == 'sztz' ? 'fbr' : 'xwfbr'],
      'summary': stripHtmlText(r['zy'] ?? r['nr'] ?? r['content'] ?? r['jj']),
      'important': r['sfzd'] == '1',
      'url': source == 'sztz'
          ? 'https://sztz.zju.edu.cn/dekt/#/index/tzgg?id=$id'
          : '${CampusService.zdbkBase}/xtgl/xwck_ckLoginNews.html?xwbh=$id',
    };
  }).toList();
}

String stripHtmlText(Object? value) {
  final raw = value?.toString() ?? '';
  if (raw.trim().isEmpty) return '';
  final withBreaks = raw.replaceAll(
    RegExp(r'<br\s*/?>', caseSensitive: false),
    '\n',
  );
  final plain = html.parse(withBreaks).body?.text ?? '';
  return plain
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n[ \t]*\n+'), '\n')
      .trim();
}
