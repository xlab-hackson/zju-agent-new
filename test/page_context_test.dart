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
import 'package:zju_campus_agent/ui/courses/course_detail_sheet.dart';

class _MemorySecrets implements SecretStore {
  final Map<String, Json> values = {};
  @override
  Future<Json?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Json value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  group('PageContext Domain & Prompts', () {
    test('dashboard context generates correct prompt and api guides', () {
      final ctx = PageContext.dashboard();
      expect(ctx.route, '/');
      expect(ctx.pageTitle, '工作台');
      expect(
        ctx.recommendedApis.any((a) => a.api == 'zju_get_upcoming_schedule'),
        isTrue,
      );
      expect(
        ctx.recommendedApis.any((a) => a.api == 'zju_get_daily_schedule'),
        isTrue,
      );

      final prompt = ctx.toPrompt();
      expect(prompt, contains('【用户当前界面上下文感知】'));
      expect(prompt, contains('当前页面：工作台 (路由: /)'));
      expect(prompt, contains('zju_get_upcoming_schedule'));
      expect(prompt, contains('zju_get_daily_schedule'));
    });

    test('courses context without active course details', () {
      final ctx = PageContext.courses(
        timetableSemester: '2025-2026-1',
        overviewSemester: 'all',
      );
      expect(ctx.route, '/courses');
      expect(ctx.pageTitle, '课程表');
      expect(ctx.details['课程表当前学期'], '2025-2026-1');
      expect(ctx.details['辅助栏(学期总览)学期'], '全部学期');
      expect(ctx.details.containsKey('当前打开的课程详情'), isFalse);

      final prompt = ctx.toPrompt();
      expect(prompt, contains('当前页面：课程表 (路由: /courses)'));
      expect(prompt, contains('课程表当前学期: 2025-2026-1'));
      expect(prompt, contains('zju_get_timetable'));
    });

    test('courses context with active course and assignment tab', () {
      final ctx = PageContext.courses(
        timetableSemester: '2025-2026-1',
        overviewSemester: '2025-2026-1',
        activeCourse: {'id': 'CS999', 'name': '计算机系统结构'},
        courseTab: 'assignments',
      );
      expect(ctx.details['当前打开的课程详情'], contains('计算机系统结构 (ID: CS999)'));
      expect(ctx.details['课程详情当前Tab'], '课程作业');

      final assignmentGuide = ctx.recommendedApis.firstWhere(
        (a) => a.api == 'zju_get_assignments',
      );
      expect(assignmentGuide.suggestedParams['courseId'], 'CS999');

      final prompt = ctx.toPrompt();
      expect(prompt, contains('计算机系统结构'));
      expect(prompt, contains('课程详情当前Tab: 课程作业'));
      expect(prompt, contains('zju_get_assignments'));
      expect(prompt, contains('"courseId":"CS999"'));
    });

    test('courses context with active course and materials tab', () {
      final ctx = PageContext.courses(
        timetableSemester: '2025-2026-1',
        overviewSemester: '2025-2026-1',
        activeCourse: {'id': 'CS101', 'name': '程序设计专题'},
        courseTab: 'materials',
      );
      expect(ctx.details['课程详情当前Tab'], '课件资料');
      final firstGuide = ctx.recommendedApis.first;
      expect(firstGuide.api, 'zju_get_course_materials');
      expect(firstGuide.suggestedParams['courseId'], 'CS101');
    });

    test('assignments context shows tab and urgent threshold', () {
      final ctx = PageContext.assignments(tab: 'pending', urgentHours: 48);
      expect(ctx.route, '/assignments');
      expect(ctx.details['当前筛选Tab'], '待提交');
      expect(ctx.details['紧急作业阈值'], '48小时');
      expect(ctx.toPrompt(), contains('待提交'));
    });

    test('exams context shows current semester', () {
      final ctx = PageContext.exams(semester: '2025-2026-2');
      expect(ctx.route, '/exams');
      expect(ctx.details['当前考试学期'], '2025-2026-2');
      expect(ctx.recommendedApis.first.api, 'zju_get_exams');
      expect(
        ctx.recommendedApis.first.suggestedParams['semester'],
        '2025-2026-2',
      );
    });

    test('school info context shows current source', () {
      final ctx = PageContext.schoolInfo(source: 'bksy');
      expect(ctx.route, '/school-info');
      expect(ctx.details['当前通知来源'], '本科生院(教务处)');
      expect(ctx.recommendedApis.first.suggestedParams['source'], 'bksy');
    });

    test('settings, downloads and classroom contexts', () {
      final settings = PageContext.settings();
      expect(settings.route, '/settings');
      expect(settings.recommendedApis, isEmpty);

      final downloads = PageContext.downloads();
      expect(downloads.route, '/downloads');
      expect(
        downloads.recommendedApis.any(
          (a) => a.api == 'zju_download_course_material',
        ),
        isTrue,
      );

      final classroom = PageContext.classroom();
      expect(classroom.route, '/classroom');
      expect(
        classroom.recommendedApis.any((a) => a.api == 'zju_get_courses'),
        isTrue,
      );
    });
  });

  group('AgentService Page Context Tool & Execution', () {
    test('toolDefinitions contains zju_get_current_page_context', () {
      final db = AgentDatabase.memory();
      final campus = CampusService(CampusSession(_MemorySecrets()), db);
      final agent = AgentService(
        campus,
        FileService(campus, Directory.systemTemp),
        GuideIndex({}),
      );
      final tools = agent.toolDefinitions();
      expect(
        tools.any((t) => t['name'] == 'zju_get_current_page_context'),
        isTrue,
      );

      final readOnlyTools = agent.toolDefinitions(readOnly: true);
      expect(
        readOnlyTools.any((t) => t['name'] == 'zju_get_current_page_context'),
        isTrue,
      );
    });

    test(
      'execute zju_get_current_page_context returns current context from tracker',
      () async {
        final db = AgentDatabase.memory();
        final campus = CampusService(CampusSession(_MemorySecrets()), db);
        PageContext current = PageContext.courses(
          timetableSemester: '2026-2027-1',
          overviewSemester: 'all',
        );

        final agent = AgentService(
          campus,
          FileService(campus, Directory.systemTemp),
          GuideIndex({}),
          getPageContext: () => current,
        );

        final result =
            await agent.execute('zju_get_current_page_context', {}) as Json;
        expect(result['route'], '/courses');
        expect(result['pageTitle'], '课程表');
        expect((result['details'] as Map)['课程表当前学期'], '2026-2027-1');

        // Update context and verify execution reflects it
        current = PageContext.assignments(tab: 'submitted');
        final updatedResult =
            await agent.execute('zju_get_current_page_context', {}) as Json;
        expect(updatedResult['route'], '/assignments');
        expect((updatedResult['details'] as Map)['当前筛选Tab'], '已提交');
      },
    );

    test('AppServices manages and updates currentPageContext', () {
      final db = AgentDatabase.memory();
      final campus = CampusService(CampusSession(_MemorySecrets()), db);
      final files = FileService(campus, Directory.systemTemp);
      final services = AppServices(
        db,
        _MemorySecrets(),
        campus,
        files,
        BackupService(db, files),
        AgentService(campus, files, GuideIndex({})),
      );

      expect(services.currentPageContext, isNull);
      services.updatePageContext(PageContext.dashboard());
      expect(services.currentPageContext?.route, '/');

      services.updatePageContext(PageContext.exams(semester: '2025-2026-1'));
      expect(services.currentPageContext?.route, '/exams');
    });
  });

  group('CourseDetailSheet onTabChanged', () {
    testWidgets(
      'triggers onTabChanged when user switches between materials and assignments tabs',
      (tester) async {
        final db = AgentDatabase.memory();
        final campus = CampusService(CampusSession(_MemorySecrets()), db);
        final files = FileService(campus, Directory.systemTemp);
        final services = AppServices(
          db,
          _MemorySecrets(),
          campus,
          files,
          BackupService(db, files),
          AgentService(campus, files, GuideIndex({})),
        );

        final now = DateTime.now();
        await db.put('cache', 'courses', {
          'items': [
            {'id': 'C100', 'name': '算法设计与分析'},
          ],
          'updatedAt': now.toUtc().toIso8601String(),
        });
        await db.put('cache', 'materials:C100', {
          'items': <Json>[],
          'updatedAt': now.toUtc().toIso8601String(),
        });
        await db.put('cache', 'assignments:C100', {
          'items': <Json>[],
          'updatedAt': now.toUtc().toIso8601String(),
        });

        final tabsReceived = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CourseDetailSheet(
                services: services,
                course: const {'id': 'C100', 'name': '算法设计与分析'},
                onDownload: (_) async {},
                onPreview: (_) async {},
                onTabChanged: (tab) => tabsReceived.add(tab),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Click on 课程作业 chip
        await tester.tap(find.text('课程作业'));
        await tester.pumpAndSettle();
        expect(tabsReceived, contains('assignments'));

        // Click on 课件资料 chip
        await tester.tap(find.text('课件资料'));
        await tester.pumpAndSettle();
        expect(tabsReceived, contains('materials'));
      },
    );
  });
}
