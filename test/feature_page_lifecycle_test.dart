import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/application/agent.dart';
import 'package:zju_campus_agent/application/campus.dart';
import 'package:zju_campus_agent/application/files.dart';
import 'package:zju_campus_agent/application/knowledge.dart';
import 'package:zju_campus_agent/application/services.dart';
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/database.dart';
import 'package:zju_campus_agent/domain/models.dart';
import 'package:zju_campus_agent/domain/schedule.dart';
import 'package:zju_campus_agent/ui/pages/feature_page.dart';

class _Secrets implements SecretStore {
  @override
  Future<Json?> read(String key) async => null;
  @override
  Future<void> write(String key, Json value) async {}
  @override
  Future<void> delete(String key) async {}
}

/// Exercises the real cache and its notifications without campus requests.
class _Campus extends CampusService {
  _Campus(super.session, super.db);

  final fetches = <String, int>{};
  final refreshRequests = <String, List<bool>>{};
  String get semester => academicSemester(beijing(DateTime.now()));
  Json get course => {'id': 'c1', 'name': '测试课程', 'semesterId': semester};

  Future<List<Json>> resource(
    String key,
    List<Json> items, {
    bool refresh = false,
  }) {
    refreshRequests.putIfAbsent(key, () => []).add(refresh);
    return cached(key, () async {
      fetches.update(key, (count) => count + 1, ifAbsent: () => 1);
      return items;
    }, refresh: refresh);
  }

  @override
  Future<List<Json>> courses({String? semesterId, bool refresh = false}) =>
      resource('courses', [course], refresh: refresh);

  @override
  Future<List<Json>> semesters({bool refresh = false}) =>
      resource('semesters', [
        {'id': semester, 'name': semester},
      ], refresh: refresh);

  @override
  Future<List<Json>> assignments({
    String? courseId,
    String? semesterId,
    List<Json>? courseCandidates,
    bool refresh = false,
  }) => resource('assignments:c1', [
    {
      'id': 'a1',
      'courseId': 'c1',
      'courseName': '测试课程',
      'title': '即将截止的作业',
      'deadline': DateTime.now()
          .add(const Duration(hours: 2))
          .toIso8601String(),
    },
    {'id': 'a2', 'title': '已经提交的作业', 'submitted': true},
  ], refresh: refresh);

  @override
  Future<List<Json>> exams(String semester, {bool refresh = false}) =>
      resource('exams:$semester', [
        {'id': 'e1', 'courseName': '测试考试'},
      ], refresh: refresh);

  @override
  Future<List<TimetableEntry>> timetable(
    String semester, {
    bool refresh = false,
  }) async {
    await resource('timetable:$semester', [], refresh: refresh);
    return [];
  }

  @override
  Future<List<Json>> grades(String semester, {bool refresh = false}) =>
      resource('grades:$semester', [], refresh: refresh);

  @override
  Future<List<Json>> enrolledCourses(String semester, {bool refresh = false}) =>
      resource('enrolled_courses:$semester', [], refresh: refresh);

  @override
  Future<Json> notices({bool refresh = false}) async => {
    'items': await resource('notices:sztz', [], refresh: refresh),
    'failures': <String>[],
  };

  @override
  Future<Json> upcoming({DateTime? now, bool refresh = false}) async => {
    'events': <Json>[],
    'semesters': await semesters(refresh: refresh),
    'courses': await courses(refresh: refresh),
    'assignments': await assignments(refresh: refresh),
    'currentTimetable': <Json>[],
    'currentExams': await exams(semester, refresh: refresh),
  };
}

void main() {
  late AgentDatabase db;
  late Directory directory;
  late _Campus campus;
  late AppServices services;

  setUp(() {
    db = AgentDatabase.memory();
    final secrets = _Secrets();
    campus = _Campus(CampusSession(secrets), db);
    directory = Directory.systemTemp.createTempSync('feature_page_lifecycle_');
    final files = FileService(campus, directory);
    services = AppServices(
      db,
      secrets,
      campus,
      files,
      BackupService(db, files),
      AgentService(campus, files, GuideIndex(const {})),
    );
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<void> showPage(
    WidgetTester tester,
    String route, {
    String? tab,
  }) async {
    // Intentionally keep the adapter's key unchanged when switching routes.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturePage(
            services: services,
            page: route,
            initialAssignmentTab: tab,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'route changes isolate filters and preserve once-per-run refresh',
    (tester) async {
      await showPage(tester, '/assignments', tab: 'urgent');
      expect(find.text('即将截止的作业'), findsOneWidget);
      expect(find.text('已经提交的作业'), findsNothing);

      await showPage(tester, '/assignments', tab: 'submitted');
      expect(find.text('即将截止的作业'), findsNothing);
      expect(find.text('已经提交的作业'), findsOneWidget);
      expect(campus.fetches['assignments:c1'], 1);

      await showPage(tester, '/exams');
      expect(find.text('测试考试'), findsOneWidget);
      expect(services.currentPageContext?.route, '/exams');

      await showPage(tester, '/assignments');
      expect(find.text('即将截止的作业'), findsOneWidget);
      expect(find.text('已经提交的作业'), findsOneWidget);
      expect(campus.refreshRequests['assignments:c1'], [true, false]);
      expect(campus.fetches['assignments:c1'], 1);

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(campus.refreshRequests['assignments:c1']!.last, isTrue);
      expect(campus.fetches['assignments:c1'], 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cache broadcasts update the active page without a forced fetch',
    (tester) async {
      await showPage(tester, '/assignments');
      await campus.cached(
        'assignments:c1',
        () async => [
          {'id': 'a3', 'title': '其他页面同步的新作业'},
        ],
        refresh: true,
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('其他页面同步的新作业'), findsOneWidget);
      expect(find.text('即将截止的作业'), findsNothing);
      expect(campus.fetches['assignments:c1'], 1);
      expect(campus.refreshRequests['assignments:c1']!.last, isFalse);

      await showPage(tester, '/downloads');
      final callsBefore = campus.refreshRequests.values.fold<int>(
        0,
        (sum, calls) => sum + calls.length,
      );
      await campus.cached('assignments:c1', () async => [], refresh: true);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(
        campus.refreshRequests.values.fold<int>(
          0,
          (sum, calls) => sum + calls.length,
        ),
        callsBefore,
      );
      expect(find.text('还没有下载过文件'), findsOneWidget);
      expect(find.textContaining('数据更新于'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [1320.0, 800.0, 390.0]) {
    testWidgets('independent pages render at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final route in [
        '/',
        '/courses',
        '/assignments',
        '/exams',
        '/school-info',
        '/downloads',
        '/classroom',
      ]) {
        await showPage(tester, route);
        expect(services.currentPageContext?.route, route);
        expect(
          tester.takeException(),
          isNull,
          reason: '$route at width $width',
        );
        if (route == '/school-info') {
          expect(find.byType(RefreshIndicator), findsNothing);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
