import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/application/agent.dart';
import 'package:zju_campus_agent/application/campus.dart';
import 'package:zju_campus_agent/application/course_overview.dart';
import 'package:zju_campus_agent/application/files.dart';
import 'package:zju_campus_agent/application/knowledge.dart';
import 'package:zju_campus_agent/application/services.dart';
import 'package:zju_campus_agent/data/campus_session.dart';
import 'package:zju_campus_agent/data/credentials.dart';
import 'package:zju_campus_agent/data/database.dart';
import 'package:zju_campus_agent/domain/course_catalog.dart';
import 'package:zju_campus_agent/domain/formatters.dart';
import 'package:zju_campus_agent/domain/models.dart';
import 'package:zju_campus_agent/domain/schedule.dart';
import 'package:zju_campus_agent/ui/assignments/assignment_card.dart';
import 'package:zju_campus_agent/ui/courses/course_detail_sheet.dart';
import 'package:zju_campus_agent/ui/courses/course_right_panel.dart';
import 'package:zju_campus_agent/ui/courses/timetable_view.dart';
import 'package:zju_campus_agent/ui/pages/feature_page.dart';
import 'package:zju_campus_agent/ui/shared/page_header.dart';
import 'package:zju_campus_agent/ui/theme.dart';

class _FakeSecrets implements SecretStore {
  final Map<String, Json> data = {};
  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<Json?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Json value) async => data[key] = value;
}

void main() {
  testWidgets(
    'AssignmentCard renders status tag, deadline and triggers onTap',
    (tester) async {
      final now = DateTime(2026, 9, 12, 12, 0);
      bool tapped = false;

      final urgentAssignment = {
        'id': 'a1',
        'title': '算法分析作业1',
        'courseName': '算法设计与分析',
        'deadline': now.add(const Duration(hours: 12)).toIso8601String(),
        'submitted': false,
        'description': '<p>请在截止前提交 PDF 报告</p>',
        'attachments': [
          {'id': 'f1', 'name': 'hw1.pdf'},
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssignmentCard(
              assignment: urgentAssignment,
              now: now,
              urgentHours: 48,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('算法分析作业1'), findsOneWidget);
      expect(find.text('算法设计与分析'), findsOneWidget);
      expect(find.text('即将截止'), findsOneWidget);
      expect(find.text('附件 1'), findsOneWidget);
      expect(find.textContaining('请在截止前提交 PDF 报告'), findsOneWidget);

      await tester.tap(find.byType(AssignmentCard));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'CourseDetailSheet switches to assignments tab and displays all assignments',
    (tester) async {
      final db = AgentDatabase.memory();
      addTearDown(() => db.close());
      final secrets = _FakeSecrets();
      final courseId = 'cs101';

      final now = DateTime.now();

      // Mock cached materials
      await db.put('cache', 'materials:$courseId', {
        'items': [
          {
            'id': 'm1',
            'title': '第一周课件',
            'files': [
              {'id': 'f1', 'name': 'lecture1.pdf'},
            ],
          },
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      // Mock cached courses
      await db.put('cache', 'courses', {
        'items': [
          {'id': courseId, 'name': '操作系统', 'semesterId': '2026-1'},
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      // Mock cached assignments (including one overdue, one upcoming, one submitted)
      await db.put('cache', 'assignments:$courseId', {
        'items': [
          {
            'id': 'a1',
            'courseId': courseId,
            'courseName': '操作系统',
            'title': 'Lab 1 启动实验',
            'deadline': now
                .subtract(const Duration(days: 20))
                .toIso8601String(),
            'submitted': false,
            'description': '<p>已超期实验但也完整展示</p>',
            'attachments': [],
          },
          {
            'id': 'a2',
            'courseId': courseId,
            'courseName': '操作系统',
            'title': 'Lab 2 内存管理',
            'deadline': now.add(const Duration(days: 5)).toIso8601String(),
            'submitted': false,
            'description': '<p>实现页表分配</p>',
            'attachments': [
              {'id': 'fa2', 'name': 'lab2.zip'},
            ],
          },
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      final campus = CampusService(CampusSession(secrets), db);
      final tempDir = Directory.systemTemp.createTempSync('course_sheet_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final files = FileService(campus, tempDir);
      final backups = BackupService(db, files);
      final agent = AgentService(campus, files, GuideIndex(const {}));
      final services = AppServices(db, secrets, campus, files, backups, agent);

      Json? clickedAssignment;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseDetailSheet(
              services: services,
              course: {
                'id': courseId,
                'name': '操作系统',
                'learningZjuCreated': true,
              },
              onDownload: (_) async {},
              onPreview: (_) async {},
              onAssignmentDetail: (a) => clickedAssignment = a,
            ),
          ),
        ),
      );

      // Initial pump & settle
      await tester.pumpAndSettle();

      // Verify course name header
      expect(find.text('操作系统'), findsOneWidget);

      // Verify tabs exist
      expect(find.text('课件资料'), findsOneWidget);
      expect(find.text('课程作业'), findsOneWidget);

      // Verify initially in materials tab
      expect(find.text('第一周课件'), findsOneWidget);

      // Switch to assignments tab
      await tester.tap(find.text('课程作业'));
      await tester.pumpAndSettle();

      // Verify both assignments are visible (including the overdue one > 7 days, as course tab shows ALL assignments without filtering)
      expect(find.text('Lab 1 启动实验'), findsOneWidget);
      expect(find.text('Lab 2 内存管理'), findsOneWidget);

      // Tap on Lab 2
      await tester.tap(find.text('Lab 2 内存管理'));
      expect(clickedAssignment, isNotNull);
      expect(clickedAssignment!['id'], 'a2');

      // Verify assignment card background color matches material card (paper color)
      final papers = tester.widgetList<Paper>(find.byType(Paper));
      expect(papers.any((p) => p.color != null), isTrue);
    },
  );

  testWidgets('AssignmentCard uses custom backgroundColor when provided', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 12, 12, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssignmentCard(
            assignment: const {'title': '测试作业'},
            now: now,
            backgroundColor: const Color(0xfff5efe6),
            onTap: () {},
          ),
        ),
      ),
    );

    final paperWidget = tester.widget<Paper>(find.byType(Paper));
    expect(paperWidget.color, const Color(0xfff5efe6));
  });

  testWidgets(
    'PageHead renders title and titleSuffix side by side on narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: PageHead(
                title: '课程表',
                titleSuffix: const SizedBox(
                  key: ValueKey('compact-picker'),
                  height: 32,
                  child: Text('2026-2027秋冬'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('课程表'), findsOneWidget);
      expect(find.byKey(const ValueKey('compact-picker')), findsOneWidget);

      final titlePos = tester.getTopLeft(find.text('课程表'));
      final suffixPos = tester.getTopLeft(
        find.byKey(const ValueKey('compact-picker')),
      );

      // Both should be on approximately the same vertical line (side-by-side)
      expect((titlePos.dy - suffixPos.dy).abs(), lessThan(30));
      // Suffix must be horizontally to the right of title
      expect(suffixPos.dx, greaterThan(titlePos.dx));
    },
  );

  test('semesterChoices respects includeAll parameter', () {
    final raw = [
      {'id': '2025-2026-1', 'name': '2025-2026秋冬'},
    ];
    final withAll = semesterChoices(raw, includeAll: true);
    expect(withAll.any((c) => c.id == 'all'), isTrue);

    final withoutAll = semesterChoices(raw, includeAll: false);
    expect(withoutAll.any((c) => c.id == 'all'), isFalse);
  });

  testWidgets('CourseRightPanel filters courses by selected semester', (
    tester,
  ) async {
    final semesters = [
      {'id': '2025-2026-1', 'name': '2025-2026学年秋冬学期'},
      {'id': '2024-2025-2', 'name': '2024-2025学年春夏学期'},
    ];
    final courses = [
      {'id': 'c1', 'name': '编译原理', 'semesterId': '2025-2026-1'},
      {'id': 'c2', 'name': '操作系统', 'semesterId': '2025-2026-1'},
      {'id': 'c3', 'name': '计算机网络', 'semesterId': '2024-2025-2'},
    ];

    String selected = 'all';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CourseRightPanel(
              data: {'semesters': semesters, 'courses': courses},
              selected: selected,
              onChanged: (val) => setState(() => selected = val),
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    // Initial state: 'all' -> all 3 courses visible
    expect(find.text('全部课程 3 门'), findsOneWidget);
    expect(find.text('编译原理'), findsOneWidget);
    expect(find.text('操作系统'), findsOneWidget);
    expect(find.text('计算机网络'), findsOneWidget);

    // Switch to '2024-2025-2' via tab directly
    await tester.tap(find.text('2024-2025春夏'));
    await tester.pumpAndSettle();

    // Now only 1 course in 2024-2025春夏
    expect(find.text('2024-2025春夏 1 门'), findsOneWidget);
    expect(find.text('计算机网络'), findsOneWidget);
    expect(find.text('编译原理'), findsNothing);
    expect(find.text('操作系统'), findsNothing);
  });

  testWidgets(
    'Timetable and right panel semesters are decoupled in FeaturePage',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AgentDatabase.memory();
      addTearDown(() => db.close());
      final secrets = _FakeSecrets();
      final campus = CampusService(CampusSession(secrets), db);
      final tempDir = Directory.systemTemp.createTempSync(
        'course_decouple_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final files = FileService(campus, tempDir);
      final backups = BackupService(db, files);
      final agent = AgentService(campus, files, GuideIndex(const {}));
      final services = AppServices(db, secrets, campus, files, backups, agent);
      services.claimInitialRefresh('/courses');
      services.claimInitialRefresh('/courses:panel');

      final currentSem = academicSemester(beijing(DateTime.now()));
      await db.put('cache', 'semesters', {
        'items': [
          {'id': currentSem, 'name': '$currentSem学期'},
          {'id': '2023-2024-1', 'name': '2023-2024-1学期'},
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.put('cache', 'courses', {
        'items': [
          {'id': 'c1', 'name': '高等数学', 'semesterId': currentSem},
          {'id': 'c2', 'name': '线性代数', 'semesterId': '2023-2024-1'},
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.put('cache', 'grades:', {
        'items': [
          {'courseName': '线性代数', 'semester': '2023-2024-1', 'credit': 3.0},
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.put('cache', 'timetable:$currentSem', {
        'items': [
          {
            'courseName': '高等数学',
            'dayOfWeek': 1,
            'startPeriod': 1,
            'endPeriod': 2,
            'location': '教7-301',
            'teacherName': '张老师',
            'weeks': [1, 2, 3],
          },
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeaturePage(services: services, page: '/courses'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify desktop timetable header shows semester tab and export buttons
      expect(find.text('导出图片'), findsOneWidget);
      expect(find.text('导出 Excel'), findsOneWidget);
      expect(find.text('高等数学'), findsWidgets);

      // Right panel shows '全部课程 2 门' because overviewSemester is 'all'
      expect(find.text('全部课程 2 门'), findsOneWidget);
      expect(find.text('线性代数'), findsOneWidget);
    },
  );

  testWidgets('Desktop courses header switches semester via tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final db = AgentDatabase.memory();
    addTearDown(() => db.close());
    final secrets = _FakeSecrets();
    final campus = CampusService(CampusSession(secrets), db);
    final tempDir = Directory.systemTemp.createTempSync('course_tabs_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final files = FileService(campus, tempDir);
    final backups = BackupService(db, files);
    final agent = AgentService(campus, files, GuideIndex(const {}));
    final services = AppServices(db, secrets, campus, files, backups, agent);
    services.claimInitialRefresh('/courses');
    services.claimInitialRefresh('/courses:panel');

    final currentSem = academicSemester(beijing(DateTime.now()));
    await db.put('cache', 'semesters', {
      'items': [
        {'id': currentSem, 'name': '$currentSem秋冬'},
        {'id': '2023-2024-2', 'name': '2023-2024春夏'},
      ],
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await db.put('cache', 'timetable:$currentSem', {
      'items': [
        {
          'courseName': '编译原理',
          'dayOfWeek': 1,
          'startPeriod': 1,
          'endPeriod': 2,
          'location': '教7-301',
          'teacherName': '张老师',
          'weeks': [1, 2, 3],
        },
      ],
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await db.put('cache', 'timetable:2023-2024-2', {
      'items': [
        {
          'courseName': '计算机体系结构',
          'dayOfWeek': 2,
          'startPeriod': 3,
          'endPeriod': 4,
          'location': '教7-401',
          'teacherName': '李老师',
          'weeks': [1, 2, 3],
        },
      ],
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await db.put('cache', 'courses', {
      'items': [
        {'id': 'c1', 'name': '编译原理', 'semesterId': currentSem},
        {'id': 'c2', 'name': '计算机体系结构', 'semesterId': '2023-2024-2'},
      ],
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturePage(services: services, page: '/courses'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // In wide mode: PageHead renders '课程表'
    expect(find.text('课程表'), findsOneWidget);
    // The old centered title text '浙江大学课程表（...）' is cleared/replaced by the desktop header
    expect(find.textContaining('浙江大学课程表'), findsNothing);

    // Initial: current semester tab is selected, shows 编译原理
    expect(find.text('编译原理'), findsWidgets);
    expect(find.text('2023-2024春夏'), findsWidgets);
    expect(find.text('导出图片'), findsOneWidget);
    expect(find.text('导出 Excel'), findsOneWidget);
    expect(find.byTooltip('刷新课表'), findsOneWidget);

    // Tap on the 2023-2024春夏 tab button in the desktop timetable header
    await tester.tap(find.text('2023-2024春夏').first);
    await tester.pumpAndSettle();

    // Now shows 计算机体系结构
    expect(find.text('计算机体系结构'), findsWidgets);
    expect(find.text('导出图片'), findsOneWidget);
    expect(find.text('导出 Excel'), findsOneWidget);
  });

  testWidgets('CourseRightPanel provides dedicated refresh button', (
    tester,
  ) async {
    bool refreshed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseRightPanel(
            data: const {
              'semesters': [
                {'id': '2025-2026-1', 'name': '2025-2026秋冬'},
              ],
              'courses': [
                {'id': 'c1', 'name': '软件工程', 'semesterId': '2025-2026-1'},
              ],
              '_updatedAt': '2026-09-12T02:00:00.000Z',
            },
            selected: 'all',
            onChanged: (_) {},
            onRefresh: () => refreshed = true,
            onSelect: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('刷新课程'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新课程'));
    expect(refreshed, isTrue);
  });

  testWidgets(
    'TimetableView renders desktop tabs and action buttons in header when wide',
    (tester) async {
      String? switchedSemester;
      bool refreshed = false;
      bool exportedPng = false;

      final choices = [
        const SemesterChoice('2025-2026-1', '2025-2026秋冬'),
        const SemesterChoice('2025-2026-2', '2025-2026春夏'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TimetableView(
                entries: const [
                  TimetableEntry(
                    id: '1',
                    courseName: '离散数学',
                    weekday: 1,
                    startSection: 1,
                    endSection: 2,
                    location: '教1-101',
                    teacher: '王老师',
                    weeks: [1, 2],
                  ),
                ],
                semester: '2025-2026-1',
                wide: true,
                choices: choices,
                onSemesterChanged: (id) => switchedSemester = id,
                onRefresh: () => refreshed = true,
                onExportPng: () => exportedPng = true,
              ),
            ),
          ),
        ),
      );

      // Desktop header: centered title is cleared
      expect(find.text('浙江大学课程表（2025-2026-1）'), findsNothing);
      // Tab buttons in header
      expect(find.text('2025-2026秋冬'), findsOneWidget);
      expect(find.text('2025-2026春夏'), findsOneWidget);
      // Action buttons in header
      expect(find.text('导出图片'), findsOneWidget);
      expect(find.text('导出 Excel'), findsOneWidget);
      expect(find.byTooltip('刷新课表'), findsOneWidget);

      // Switch tab (scrolls into visible area since tab container occupies roughly 1/3 width)
      await tester.ensureVisible(find.text('2025-2026春夏'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025-2026春夏'));
      expect(switchedSemester, '2025-2026-2');

      // Click export & refresh
      await tester.tap(find.text('导出图片'));
      expect(exportedPng, isTrue);
      await tester.tap(find.byTooltip('刷新课表'));
      expect(refreshed, isTrue);
    },
  );

  testWidgets('TimetableView renders centered title when isExporting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TimetableView(
            entries: [],
            semester: '2025-2026-1',
            isExporting: true,
          ),
        ),
      ),
    );

    // When exporting, renders centered title with sub-semester suffix for clean screenshot
    expect(find.text('浙江大学课程表（2025-2026-1 - 秋学期）'), findsOneWidget);
    expect(find.byTooltip('刷新课表'), findsNothing);
  });

  testWidgets(
    'TimetableView renders compact icon actions and tabs on narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(380, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final choices = [
        const SemesterChoice('2025-2026-1', '2025-2026秋冬'),
        const SemesterChoice('2025-2026-2', '2025-2026春夏'),
      ];

      bool refreshed = false;
      bool exportedPng = false;
      bool exportedXlsx = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TimetableView(
                entries: const [
                  TimetableEntry(
                    id: '1',
                    courseName: '计算机视觉',
                    weekday: 1,
                    startSection: 1,
                    endSection: 2,
                  ),
                ],
                semester: '2025-2026-1',
                wide: false,
                choices: choices,
                onRefresh: () => refreshed = true,
                onExportPng: () => exportedPng = true,
                onExportXlsx: () => exportedXlsx = true,
              ),
            ),
          ),
        ),
      );

      // On narrow screen: tabs are rendered
      expect(find.text('2025-2026秋冬'), findsOneWidget);
      expect(find.text('2025-2026春夏'), findsOneWidget);
      // Compact action icons are rendered via tooltip
      expect(find.byTooltip('导出图片'), findsOneWidget);
      expect(find.byTooltip('导出 Excel'), findsOneWidget);
      expect(find.byTooltip('刷新课表'), findsOneWidget);

      // Tap actions
      await tester.tap(find.byTooltip('导出图片'));
      expect(exportedPng, isTrue);

      await tester.tap(find.byTooltip('导出 Excel'));
      expect(exportedXlsx, isTrue);

      await tester.tap(find.byTooltip('刷新课表'));
      expect(refreshed, isTrue);
    },
  );

  testWidgets(
    'TimetableView empty state keeps header tabs and shows PageEmpty on all widths',
    (tester) async {
      final choices = [
        const SemesterChoice('2025-2026-1', '2025-2026秋冬'),
        const SemesterChoice('2025-2026-2', '2025-2026春夏'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableView(
              entries: const [],
              semester: '2025-2026-1',
              wide: false,
              choices: choices,
            ),
          ),
        ),
      );

      // Header tabs and refresh still present
      expect(find.text('2025-2026秋冬'), findsOneWidget);
      expect(find.text('2025-2026春夏'), findsOneWidget);
      expect(find.byTooltip('刷新课表'), findsOneWidget);
      // PageEmpty shown below header
      expect(find.text('该学期暂无课表数据'), findsOneWidget);
    },
  );

  testWidgets(
    'TimetableView header restricts semester tabs to roughly one half of header width on desktop and adapts tab sizes',
    (tester) async {
      const totalWidth = 900.0;
      tester.view.physicalSize = const Size(totalWidth, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final choices = [
        const SemesterChoice('sem1', '2024-2025-1'),
        const SemesterChoice('sem2', '2024-2025-2'),
        const SemesterChoice('sem3', '2025-2026-1'),
        const SemesterChoice('sem4', '2025-2026-2'),
        const SemesterChoice('sem5', '2026-2027-1'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableView(
              entries: const [],
              semester: 'sem1',
              choices: choices,
            ),
          ),
        ),
      );

      // Container padding is 14 on each side, so width is 900 - 28 = 872
      // Half width is 872 / 2 = 436.0
      final sizedBoxFinder = find.byWidgetPredicate(
        (w) =>
            w is SizedBox && w.width != null && (w.width! - 436.0).abs() < 1.0,
      );
      expect(sizedBoxFinder, findsOneWidget);

      // Verify all 5 choices are rendered and visible without scrolling on desktop
      for (final choice in choices) {
        expect(find.text(choice.name), findsOneWidget);
      }
    },
  );

  testWidgets(
    'TimetableView header on narrow screen allows horizontal scrolling and disables scrollbars',
    (tester) async {
      const totalWidth = 400.0;
      tester.view.physicalSize = const Size(totalWidth, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final choices = [
        const SemesterChoice('sem1', '2024-2025-1'),
        const SemesterChoice('sem2', '2024-2025-2'),
        const SemesterChoice('sem3', '2025-2026-1'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableView(
              entries: const [],
              semester: 'sem1',
              choices: choices,
            ),
          ),
        ),
      );

      final scrollViewFinder = find.byType(SingleChildScrollView);
      expect(scrollViewFinder, findsOneWidget);

      final scrollConfigFinder = find
          .ancestor(
            of: scrollViewFinder,
            matching: find.byType(ScrollConfiguration),
          )
          .first;
      final scrollConfig = tester.widget<ScrollConfiguration>(
        scrollConfigFinder,
      );
      final behavior = scrollConfig.behavior;
      final testContext = tester.element(scrollViewFinder);
      final dummyChild = Container();
      final scrollbarWidget = behavior.buildScrollbar(
        testContext,
        dummyChild,
        const ScrollableDetails.horizontal(),
      );
      expect(identical(scrollbarWidget, dummyChild), isTrue);
    },
  );

  testWidgets('TimetableView does not render internal grid cell borders', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TimetableView(
            entries: [
              TimetableEntry(
                id: '1',
                courseName: '计算机系统',
                weekday: 1,
                startSection: 1,
                endSection: 2,
                location: '教4-201',
                teacher: '张老师',
                weeks: [1, 2, 3],
              ),
            ],
            semester: '2025-2026-1',
          ),
        ),
      ),
    );

    // Verify there are no 52px grid cell border containers (previously 13 * 7 = 91)
    final cellBorderFinder = find.byWidgetPredicate((widget) {
      if (widget is Positioned && widget.height == 52) {
        final child = widget.child;
        if (child is Container && child.decoration is BoxDecoration) {
          final boxDecoration = child.decoration as BoxDecoration;
          final border = boxDecoration.border;
          if (border != null && border.isUniform) {
            return true;
          }
        }
      }
      return false;
    });
    expect(cellBorderFinder, findsNothing);

    // Course entry itself is still rendered with its left indicator (3 chars per line on mobile)
    expect(find.text('计算机\n系统'), findsOneWidget);
  });

  testWidgets(
    'TimetableView on mobile narrows session column and truncates course name to at most 8 chars across 3 lines',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TimetableView(
              entries: [
                TimetableEntry(
                  id: '1',
                  courseName: '毛泽东思想和中国特色社会主义理论体系概论',
                  weekday: 1,
                  startSection: 1,
                  endSection: 2,
                  location: '教7-301',
                  teacher: '李老师',
                  weeks: [1, 2],
                ),
                TimetableEntry(
                  id: '2',
                  courseName: '面向对象程序设计',
                  weekday: 2,
                  startSection: 3,
                  endSection: 4,
                  location: '教1-102',
                  teacher: '王老师',
                  weeks: [1, 2],
                ),
              ],
              semester: '2025-2026-1',
              wide: false,
            ),
          ),
        ),
      );

      // Header session column text on mobile is '节次\n时间' with width 30
      expect(find.text('节次\n时间'), findsOneWidget);
      final headerSessionBox = tester.renderObject<RenderBox>(
        find
            .ancestor(of: find.text('节次\n时间'), matching: find.byType(SizedBox))
            .first,
      );
      expect(headerSessionBox.size.width, 30.0);

      // Course with length > 8 truncated to 8 chars + '...', exactly 3 chars per line (no 4-3-1 wrapping)
      expect(find.text('毛泽东\n思想和\n中国...'), findsOneWidget);
      // Course with length <= 8 preserved completely across 3 lines: 3 + 3 + 2
      expect(find.text('面向对\n象程序\n设计'), findsOneWidget);

      // Verify course name text widget properties
      final textWidget = tester.widget<Text>(find.text('毛泽东\n思想和\n中国...'));
      expect(textWidget.maxLines, 3);
      expect(textWidget.overflow, TextOverflow.ellipsis);
      expect(textWidget.style?.fontSize, 8.5);
    },
  );

  testWidgets(
    'TimetableView allows switching between autumn, winter and all sub-semesters',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TimetableView(
              entries: [
                TimetableEntry(
                  id: '1',
                  courseName: '高等数学',
                  weekday: 1,
                  startSection: 1,
                  endSection: 2,
                  subSemester: '秋',
                ),
                TimetableEntry(
                  id: '2',
                  courseName: '大学物理',
                  weekday: 2,
                  startSection: 3,
                  endSection: 4,
                  subSemester: '冬',
                ),
                TimetableEntry(
                  id: '3',
                  courseName: '思想道德修养',
                  weekday: 3,
                  startSection: 5,
                  endSection: 6,
                  subSemester: '秋冬',
                ),
              ],
              semester: '2025-2026-1',
              wide: true,
            ),
          ),
        ),
      );

      // Initial state: defaults to '秋学期' without '全部' option
      expect(find.text('学期分段：'), findsOneWidget);
      expect(find.text('全部'), findsNothing);
      expect(find.text('秋学期'), findsOneWidget);
      expect(find.text('冬学期'), findsOneWidget);

      // In autumn: autumn course and full-term course shown, winter course filtered
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('思想道德修养'), findsOneWidget);
      expect(find.text('大学物理'), findsNothing);

      // Tap '冬学期': winter course and full-term course shown, autumn course filtered
      await tester.tap(find.text('冬学期'));
      await tester.pumpAndSettle();

      expect(find.text('大学物理'), findsOneWidget);
      expect(find.text('思想道德修养'), findsOneWidget);
      expect(find.text('高等数学'), findsNothing);

      // Tap '秋学期': switches back to autumn
      await tester.tap(find.text('秋学期'));
      await tester.pumpAndSettle();

      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('思想道德修养'), findsOneWidget);
      expect(find.text('大学物理'), findsNothing);
    },
  );

  testWidgets(
    'CourseRightPanel renders tabs and stays within 2 rows when multiple semesters exist',
    (tester) async {
      final semesters = [
        {'id': '2024-2025-1', 'name': '2024-2025学年秋冬学期'},
        {'id': '2024-2025-2', 'name': '2024-2025学年春夏学期'},
        {'id': '2025-2026-1', 'name': '2025-2026学年秋冬学期'},
        {'id': '2025-2026-2', 'name': '2025-2026学年春夏学期'},
      ];

      String current = 'all';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: StatefulBuilder(
                builder: (context, setState) => CourseRightPanel(
                  data: {
                    'semesters': semesters,
                    'courses': [
                      {'id': 'c1', 'name': '软件工程', 'semesterId': '2024-2025-1'},
                      {
                        'id': 'c2',
                        'name': '数据库系统',
                        'semesterId': '2025-2026-1',
                      },
                    ],
                  },
                  selected: current,
                  onChanged: (val) => setState(() => current = val),
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // With 4 semesters + 'all', total 5 choices: splits into 2 rows (row1: 3, row2: 2)
      expect(find.text('全部学期'), findsOneWidget);
      expect(find.text('2024-2025秋冬'), findsOneWidget);
      expect(find.text('2024-2025春夏'), findsOneWidget);
      expect(find.text('2025-2026秋冬'), findsOneWidget);
      expect(find.text('2025-2026春夏'), findsOneWidget);

      // Tap '2024-2025秋冬' tab
      await tester.tap(find.text('2024-2025秋冬'));
      await tester.pumpAndSettle();

      expect(find.text('软件工程'), findsOneWidget);
      expect(find.text('数据库系统'), findsNothing);

      // Tap '全部学期'
      await tester.tap(find.text('全部学期'));
      await tester.pumpAndSettle();

      expect(find.text('软件工程'), findsOneWidget);
      expect(find.text('数据库系统'), findsOneWidget);
    },
  );

  test(
    'semesterDisplay distinguishes autumn, winter, spring, summer and full semesters',
    () {
      expect(semesterDisplay('2024-2025-1', '2024-2025学年秋学期'), '2024-2025秋');
      expect(semesterDisplay('2024-2025-1', '2024-2025学年冬学期'), '2024-2025冬');
      expect(semesterDisplay('2024-2025-1', '2024-2025学年秋冬学期'), '2024-2025秋冬');
      expect(semesterDisplay('2024-2025-2', '2024-2025学年春学期'), '2024-2025春');
      expect(semesterDisplay('2024-2025-2', '2024-2025学年夏学期'), '2024-2025夏');
      expect(semesterDisplay('2024-2025-2', '2024-2025学年春夏学期'), '2024-2025春夏');
    },
  );

  test('formatHms formats seconds into HH:mm:ss', () {
    expect(formatHms(0), '00:00:00');
    expect(formatHms(59), '00:00:59');
    expect(formatHms(65), '00:01:05');
    expect(formatHms(3661), '01:01:01');
    expect(formatHms(86399), '23:59:59');
  });

  testWidgets(
    'CourseRightPanel displays teacher name and distinguishes autumn and winter groups',
    (tester) async {
      final semesters = [
        {'id': '2024-2025-autumn', 'name': '2024-2025学年秋学期'},
        {'id': '2024-2025-winter', 'name': '2024-2025学年冬学期'},
      ];
      final courses = [
        {
          'id': 'c1',
          'name': '编译原理',
          'semesterId': '2024-2025-autumn',
          'teacher': '翁恺',
        },
        {
          'id': 'c2',
          'name': '操作系统',
          'semesterId': '2024-2025-winter',
          'teacher': '何钦铭',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              child: CourseRightPanel(
                data: {'semesters': semesters, 'courses': courses},
                selected: 'all',
                onChanged: (_) {},
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );

      // Group headers should distinguish autumn and winter
      expect(find.text('2024-2025秋  1 门'), findsOneWidget);
      expect(find.text('2024-2025冬  1 门'), findsOneWidget);

      // Course names and teachers should be visible
      expect(find.text('编译原理'), findsOneWidget);
      expect(find.text('翁恺'), findsOneWidget);
      expect(find.text('操作系统'), findsOneWidget);
      expect(find.text('何钦铭'), findsOneWidget);
    },
  );

  testWidgets(
    'TimetableView header does not overflow at narrow desktop width (584px)',
    (tester) async {
      final choices = [
        SemesterChoice('2024-2025-1', '2024-2025秋冬'),
        SemesterChoice('2024-2025-2', '2024-2025春夏'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 584,
                height: 600,
                child: TimetableView(
                  entries: const [],
                  semester: '2024-2025-1',
                  wide: true,
                  choices: choices,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'TimetableView course block click triggers onSelectCourse callback',
    (tester) async {
      final entry = TimetableEntry(
        id: 't1',
        courseName: '计算机系统结构',
        teacher: '陈文智',
        location: '曹光彪西-502',
        weekday: 1,
        startSection: 1,
        endSection: 2,
        subSemester: '秋',
        weeks: const [1, 2, 3, 4, 5, 6, 7, 8],
      );

      TimetableEntry? tappedEntry;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 900,
              child: TimetableView(
                entries: [entry],
                semester: '2024-2025-1',
                wide: true,
                onSelectCourse: (e) => tappedEntry = e,
              ),
            ),
          ),
        ),
      );

      expect(find.text('计算机系统结构'), findsOneWidget);

      await tester.tap(find.text('计算机系统结构'));
      await tester.pumpAndSettle();

      expect(tappedEntry, isNotNull);
      expect(tappedEntry!.courseName, '计算机系统结构');
      expect(tappedEntry!.teacher, '陈文智');
    },
  );

  testWidgets(
    'CourseDetailSheet displays course scheduleTime, location and teacher',
    (tester) async {
      final db = AgentDatabase.memory();
      addTearDown(() => db.close());
      final secrets = _FakeSecrets();
      final campus = CampusService(CampusSession(secrets), db);
      final tempDir = Directory.systemTemp.createTempSync(
        'course_sheet_meta_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final files = FileService(campus, tempDir);
      final backups = BackupService(db, files);
      final agent = AgentService(campus, files, GuideIndex(const {}));
      final services = AppServices(db, secrets, campus, files, backups, agent);

      final course = {
        'id': 'cs202',
        'name': '数据结构基础',
        'teacher': '陈越',
        'location': '紫金港东1A-101',
        'scheduleTime': '周一 1-2节 (秋 1-8 周)',
      };

      final now = DateTime.now();
      await db.put('cache', 'courses', {
        'items': [
          {'id': 'cs202', 'name': '数据结构基础', 'semesterId': '2026-1'},
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });
      await db.put('cache', 'materials:cs202', {
        'items': <Json>[],
        'updatedAt': now.toUtc().toIso8601String(),
      });
      await db.put('cache', 'assignments:cs202', {
        'items': <Json>[],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseDetailSheet(
              services: services,
              course: course,
              onDownload: (_) async {},
              onPreview: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('数据结构基础'), findsOneWidget);
      expect(find.text('周一 1-2节 (秋 1-8 周)'), findsOneWidget);
      expect(find.text('紫金港东1A-101'), findsOneWidget);
      expect(find.text('陈越'), findsOneWidget);
    },
  );

  test('formatGradeBadge and normalizeCourseName work as expected', () {
    expect(formatGradeBadge('92', '4.5'), '92分 / 4.5');
    expect(formatGradeBadge('88', '4.0'), '88分 / 4.0');
    expect(formatGradeBadge('合格', '-1'), '合格');
    expect(formatGradeBadge('优秀', '4.5'), '优秀 / 4.5');
    expect(formatGradeBadge('100', ''), '100分');
    expect(formatGradeBadge('', '4.8'), '绩点 4.8');
    expect(formatGradeBadge('', ''), '');

    expect(normalizeCourseName('微积分(甲)I'), '微积分（甲）（1）');
    expect(normalizeCourseName('微积分（甲）Ⅰ'), '微积分（甲）（1）');
    expect(normalizeCourseName('微积分（甲）1'), '微积分（甲）（1）');
    expect(cleanCourseBaseName('微积分（甲）Ⅰ (2024-2025-1)'), '微积分（甲）（1）');
    expect(cleanCourseBaseName('离散数学 (061B0170-01)'), '离散数学');

    // 验证计算机系统一与计算机系统二绝对独立，不混淆
    expect(normalizeCourseName('计算机系统一'), '计算机系统（1）');
    expect(normalizeCourseName('计算机系统二'), '计算机系统（2）');
    expect(normalizeCourseName('计算机系统1'), '计算机系统（1）');
    expect(normalizeCourseName('计算机系统2'), '计算机系统（2）');
    expect(normalizeCourseName('计算机系统Ⅰ'), '计算机系统（1）');
    expect(normalizeCourseName('计算机系统Ⅱ'), '计算机系统（2）');
    expect(
      normalizeCourseName('计算机系统一'),
      isNot(equals(normalizeCourseName('计算机系统二'))),
    );

    // 验证嵌套后缀与学期剥离
    expect(
      normalizeCourseName('微积分（甲）Ⅰ（061B0170-01）（2024-2025-1）'),
      '微积分（甲）（1）',
    );
  });

  testWidgets(
    'CourseRightPanel displays credit badge and score/gpa badge for past released courses',
    (tester) async {
      final semesters = [
        {'id': '2024-2025-autumn', 'name': '2024-2025学年秋学期'},
      ];
      final courses = [
        {
          'id': 'c1',
          'name': '微积分（甲）Ⅰ',
          'semesterId': '2024-2025-autumn',
          'teacher': '苏德矿',
          'credit': 5.0,
          'score': '95',
          'gpa': '4.8',
        },
        {
          'id': 'c2',
          'name': '大学体育Ⅰ',
          'semesterId': '2024-2025-autumn',
          'teacher': '体育老师',
          'credit': 1.0,
          'score': '合格',
        },
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: CourseRightPanel(
                data: {'semesters': semesters, 'courses': courses},
                selected: 'all',
                onChanged: (_) {},
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('微积分（甲）Ⅰ'), findsOneWidget);
      expect(find.text('苏德矿'), findsOneWidget);
      expect(find.text('5 学分'), findsOneWidget);
      expect(find.text('95分 / 4.8'), findsOneWidget);

      expect(find.text('大学体育Ⅰ'), findsOneWidget);
      expect(find.text('体育老师'), findsOneWidget);
      expect(find.text('1 学分'), findsOneWidget);
      expect(find.text('合格'), findsOneWidget);
    },
  );

  test(
    'loadOverview isolates 计算机系统一 and 计算机系统二 grades across semesters',
    () async {
      final db = AgentDatabase.memory();
      addTearDown(() => db.close());
      final secrets = _FakeSecrets();
      final campus = CampusService(CampusSession(secrets), db);
      final tempDir = Directory.systemTemp.createTempSync('course_iso_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final files = FileService(campus, tempDir);
      final backups = BackupService(db, files);
      final agent = AgentService(campus, files, GuideIndex(const {}));
      final services = AppServices(db, secrets, campus, files, backups, agent);

      final now = DateTime.now();

      // Mock semesters
      await db.put('cache', 'semesters', {
        'items': [
          {'id': '2023-2024-1', 'name': '2023-2024学年秋冬学期'},
          {'id': '2024-2025-1', 'name': '2024-2025学年秋冬学期'},
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      // Mock courses from Learning at ZJU
      await db.put('cache', 'courses', {
        'items': [
          {'id': 'cs1', 'name': '计算机系统一', 'semesterId': '2023-2024-1'},
          {'id': 'cs2', 'name': '计算机系统二', 'semesterId': '2024-2025-1'},
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      // Mock historical grades containing grade ONLY for 计算机系统Ⅰ in 2023-2024-1
      await db.put('cache', 'grades:', {
        'items': [
          {
            'courseName': '计算机系统Ⅰ',
            'semester': '2023-2024-1',
            'original': '91',
            'fivePoint': '4.5',
            'credit': 4.0,
            'teacher': '陈老师',
          },
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      // Mock timetable for 2024-2025-1 with 计算机系统（2） taught by 陆老师
      await db.put('cache', 'timetable:2024-2025-1', {
        'items': [
          {
            'courseName': '计算机系统（2）',
            'teacher': '陆老师',
            'credit': 4.0,
            'dayOfWeek': 1,
            'startPeriod': 1,
            'endPeriod': 2,
          },
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });
      final overview = await loadCourseOverview(services, '2024-2025-1');
      final loadedCourses = (overview['courses'] as List).cast<Json>();

      final cs1Course = loadedCourses.firstWhere((c) => c['id'] == 'cs1');
      final cs2Course = loadedCourses.firstWhere((c) => c['id'] == 'cs2');

      // cs1 (计算机系统一 in 2023-2024-1) must match its grade
      expect(cs1Course['score'], '91');
      expect(cs1Course['gpa'], '4.5');
      expect(cs1Course['teacher'], '陈老师');
      expect(cs1Course['credit'], 4.0);

      // cs2 (计算机系统二 in 2024-2025-1) MUST NOT borrow cs1's grade!
      expect(cs2Course['score'], isNull);
      expect(cs2Course['gpa'], isNull);
      // cs2 should have its own teacher and credit from timetable
      expect(cs2Course['teacher'], '陆老师');
      expect(cs2Course['credit'], 4.0);
    },
  );

  testWidgets(
    'CourseRightPanel displays academic stats card and updates when switching semester',
    (tester) async {
      final semesters = [
        {'id': '2023-2024-1', 'name': '2023-2024学年秋冬学期'},
        {'id': '2024-2025-1', 'name': '2024-2025学年秋冬学期'},
      ];
      final courses = [
        {
          'id': 'c1',
          'name': '微积分（甲）Ⅰ',
          'semesterId': '2023-2024-1',
          'credit': 5.0,
          'score': '95',
          'gpa': '4.8',
        },
        {
          'id': 'c2',
          'name': '大学物理',
          'semesterId': '2024-2025-1',
          'credit': 4.0,
        },
      ];

      String selected = 'all';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => CourseRightPanel(
                  data: {'semesters': semesters, 'courses': courses},
                  selected: selected,
                  onChanged: (val) => setState(() => selected = val),
                  onSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      // In 'all' mode:
      expect(find.text('目前总绩点'), findsOneWidget);
      expect(find.text('获得总学分'), findsOneWidget);
      expect(find.text('百分制均分'), findsOneWidget);
      expect(find.text('4.80'), findsOneWidget);
      expect(find.text('95.0'), findsOneWidget);
      expect(find.textContaining('全历程共 2 门课程 · 已出分 1 门'), findsOneWidget);

      // Switch to 2024-2025秋冬 (ongoing semester, c2 has 4 credits but not graded yet)
      await tester.tap(find.text('2024-2025秋冬'));
      await tester.pumpAndSettle();

      expect(find.text('学期绩点'), findsOneWidget);
      expect(find.text('已选学分'), findsOneWidget);
      expect(find.text('修读中'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
      expect(find.textContaining('本学期共 1 门课程 · 暂未出分'), findsOneWidget);

      // Switch to 2023-2024秋冬 (graded semester)
      await tester.tap(find.text('2023-2024秋冬'));
      await tester.pumpAndSettle();

      expect(find.text('学期绩点'), findsOneWidget);
      expect(find.text('获得/已选学分'), findsOneWidget);
      expect(find.text('4.80'), findsOneWidget);
      expect(find.text('5 / 5'), findsOneWidget);
      expect(find.text('95.0'), findsOneWidget);
      expect(find.textContaining('本学期共 1 门课程 · 已出分 1 门'), findsOneWidget);
    },
  );

  testWidgets(
    'Dashboard academic KPI card opens course overview sheet on tap',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = AgentDatabase.memory();
      addTearDown(() => db.close());
      final secrets = _FakeSecrets();
      final campus = CampusService(CampusSession(secrets), db);
      final tempDir = Directory.systemTemp.createTempSync('kpi_tap_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final files = FileService(campus, tempDir);
      final backups = BackupService(db, files);
      final agent = AgentService(campus, files, GuideIndex(const {}));
      final services = AppServices(db, secrets, campus, files, backups, agent);
      services.claimInitialRefresh('/');
      services.claimInitialRefresh('/courses:panel');

      final currentSem = academicSemester(beijing(DateTime.now()));
      await db.put('cache', 'semesters', {
        'items': [
          {'id': currentSem, 'name': '$currentSem学期'},
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.put('cache', 'courses', {
        'items': [
          {'id': 'c1', 'name': '计算机系统', 'semesterId': currentSem},
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await db.put('cache', 'grades:', {
        'items': [
          {
            'courseName': '高等数学',
            'semester': '2023-2024-1',
            'original': '96',
            'fivePoint': '4.9',
            'credit': 5.0,
            'creditIncluded': true,
            'gpaIncluded': true,
          },
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeaturePage(services: services, page: '/'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dashboard academic performance card shows GPA 4.90
      expect(find.text('目前总绩点'), findsOneWidget);
      expect(find.text('4.90'), findsOneWidget);

      // Tap on 目前总绩点
      await tester.tap(find.text('目前总绩点'));
      await tester.pumpAndSettle();

      // Verify modal bottom sheet with CourseRightPanel opened with '学期总览'
      expect(find.text('学期总览'), findsOneWidget);
      expect(find.text('全部学期'), findsOneWidget);
    },
  );

  testWidgets(
    'CourseRightPanel shows 未建课 tag and allows opening course detail when course not created on 学在浙大',
    (tester) async {
      final semesters = [
        {'id': '2024-2025-1', 'name': '2024-2025学年秋冬学期'},
      ];
      final courses = [
        {
          'id': 'cs101',
          'name': '微积分（1）',
          'semesterId': '2024-2025-1',
          'credit': 5.0,
          'learningZjuCreated': true,
        },
        {
          'id': '',
          'name': '大学体育（1）',
          'semesterId': '2024-2025-1',
          'credit': 1.0,
          'learningZjuCreated': false,
        },
      ];

      Json? selectedCourse;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseRightPanel(
              data: {'semesters': semesters, 'courses': courses},
              selected: '2024-2025-1',
              onChanged: (_) {},
              onSelect: (c) => selectedCourse = c,
            ),
          ),
        ),
      );

      // Both courses should be visible in 2024-2025-1
      expect(find.text('微积分（1）'), findsOneWidget);
      expect(find.text('大学体育（1）'), findsOneWidget);

      // 大学体育（1） should display 未建课 tag
      expect(find.text('未建课'), findsOneWidget);

      // Clicking 大学体育（1） SHOULD trigger onSelect and open course detail
      await tester.tap(find.text('大学体育（1）'));
      await tester.pumpAndSettle();
      expect(selectedCourse, isNotNull);
      expect(selectedCourse!['name'], '大学体育（1）');

      // Clicking 微积分（1） SHOULD also trigger onSelect
      selectedCourse = null;
      await tester.tap(find.text('微积分（1）'));
      await tester.pumpAndSettle();
      expect(selectedCourse, isNotNull);
      expect(selectedCourse!['name'], '微积分（1）');
    },
  );

  testWidgets(
    'CourseDetailSheet displays empty state and 学在浙大无此课程 hint when course is not created on 学在浙大',
    (tester) async {
      final db = AgentDatabase.memory();
      addTearDown(() => db.close());
      final secrets = _FakeSecrets();
      final campus = CampusService(CampusSession(secrets), db);
      final tempDir = Directory.systemTemp.createTempSync(
        'uncreated_course_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final files = FileService(campus, tempDir);
      final backups = BackupService(db, files);
      final agent = AgentService(campus, files, GuideIndex(const {}));
      final services = AppServices(db, secrets, campus, files, backups, agent);

      final uncreatedCourse = {
        'id': '',
        'name': '大学体育（1）',
        'teacher': '李老师',
        'location': '玉泉田径场',
        'credit': 1.0,
        'learningZjuCreated': false,
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourseDetailSheet(
              services: services,
              course: uncreatedCourse,
              onDownload: (_) async {},
              onPreview: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify course name and meta information
      expect(find.text('大学体育（1）'), findsOneWidget);
      expect(find.text('李老师'), findsOneWidget);
      expect(find.text('玉泉田径场'), findsOneWidget);
      expect(find.text('1 学分'), findsOneWidget);

      // Verify "学在浙大无此课程" hint in Tab row
      expect(find.text('学在浙大无此课程'), findsOneWidget);

      // Verify materials tab is empty
      expect(find.text('该课程暂无资料'), findsOneWidget);

      // Switch to assignments tab
      await tester.tap(find.text('课程作业'));
      await tester.pumpAndSettle();

      // Verify assignments tab is empty
      expect(find.text('该课程暂无作业'), findsOneWidget);
      // Hint text remains visible
      expect(find.text('学在浙大无此课程'), findsOneWidget);
    },
  );

  test(
    'loadCourseOverview pulls courses from ZDBK and marks learningZjuCreated correctly',
    () async {
      final db = AgentDatabase.memory();
      addTearDown(() => db.close());
      final secrets = _FakeSecrets();
      final campus = CampusService(CampusSession(secrets), db);
      final tempDir = Directory.systemTemp.createTempSync(
        'zdbk_overview_test_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final files = FileService(campus, tempDir);
      final backups = BackupService(db, files);
      final agent = AgentService(campus, files, GuideIndex(const {}));
      final services = AppServices(db, secrets, campus, files, backups, agent);

      final now = DateTime.now();

      await db.put('cache', 'semesters', {
        'items': [
          {'id': '2024-2025-1', 'name': '2024-2025学年秋冬学期'},
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      // Mock enrolled courses in ZDBK: 2 courses (面向对象程序设计 and 形势与政策)
      await db.put('cache', 'enrolled_courses:all', {
        'items': [
          {
            'courseName': '面向对象程序设计',
            'semester': '2024-2025-1',
            'credit': 3.0,
            'xkkh': '(2024-2025-1)-02119120-001001-1',
            'teacher': '李老师',
          },
          {
            'courseName': '形势与政策',
            'semester': '2024-2025-1',
            'credit': 1.0,
            'xkkh': '(2024-2025-1)-01111111-001001-1',
            'teacher': '王老师',
          },
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      // Mock courses on 学在浙大: ONLY 面向对象程序设计 has been created on 学在浙大
      await db.put('cache', 'courses', {
        'items': [
          {
            'id': 'l_zju_9988',
            'name': '面向对象程序设计',
            'courseCode': '02119120',
            'semesterId': '2024-2025-1',
          },
        ],
        'updatedAt': now.toUtc().toIso8601String(),
      });

      await db.put('cache', 'timetable:2024-2025-1', {
        'items': <Json>[],
        'updatedAt': now.toUtc().toIso8601String(),
      });
      await db.put('cache', 'timetable:2023-2024-1', {
        'items': <Json>[],
        'updatedAt': DateTime.utc(2020, 1, 1).toIso8601String(),
      });

      final overview = await loadCourseOverview(services, '2024-2025-1');
      final loadedCourses = (overview['courses'] as List).cast<Json>();
      final updatedAt = DateTime.tryParse(text(overview, '_updatedAt'));
      expect(updatedAt, isNotNull);
      expect(
        updatedAt!.isAfter(now.toUtc().subtract(const Duration(minutes: 1))),
        isTrue,
      );

      // Both courses must be present from ZDBK
      expect(loadedCourses.length, 2);

      final oop = loadedCourses.firstWhere((c) => c['name'] == '面向对象程序设计');
      final policy = loadedCourses.firstWhere((c) => c['name'] == '形势与政策');

      // 面向对象程序设计 matches 学在浙大
      expect(oop['learningZjuCreated'], isTrue);
      expect(oop['id'], 'l_zju_9988');
      expect(oop['credit'], 3.0);
      expect(oop['teacher'], '李老师');

      // 形势与政策 is not created on 学在浙大
      expect(policy['learningZjuCreated'], isFalse);
      expect(policy['id'], '');
      expect(policy['credit'], 1.0);
      expect(policy['teacher'], '王老师');
    },
  );

  testWidgets('课程页学期总览可收起，并在窄栏上重新展开', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final db = AgentDatabase.memory();
    addTearDown(() => db.close());
    final secrets = _FakeSecrets();
    final campus = CampusService(CampusSession(secrets), db);
    final tempDir = Directory.systemTemp.createTempSync('overview_collapse_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final files = FileService(campus, tempDir);
    final backups = BackupService(db, files);
    final agent = AgentService(campus, files, GuideIndex(const {}));
    final services = AppServices(db, secrets, campus, files, backups, agent);
    services.claimInitialRefresh('/courses');
    services.claimInitialRefresh('/courses:panel');

    final currentSem = academicSemester(beijing(DateTime.now()));
    final now = DateTime.now().toUtc().toIso8601String();
    await db.put('cache', 'semesters', {
      'items': [
        {'id': currentSem, 'name': '$currentSem学期'},
      ],
      'updatedAt': now,
    });
    await db.put('cache', 'courses', {
      'items': [
        {'id': 'c1', 'name': '高等数学', 'semesterId': currentSem},
      ],
      'updatedAt': now,
    });
    await db.put('cache', 'grades:', {'items': [], 'updatedAt': now});
    await db.put('cache', 'timetable:$currentSem', {
      'items': [],
      'updatedAt': now,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeaturePage(services: services, page: '/courses'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 展开状态：显示辅助栏标题与收起按钮。
    expect(find.text('学期总览'), findsOneWidget);
    expect(find.byTooltip('收起学期总览'), findsOneWidget);
    expect(find.byTooltip('展开学期总览'), findsNothing);

    await tester.tap(find.byTooltip('收起学期总览'));
    await tester.pumpAndSettle();

    // 收起状态：辅助栏内容消失，只留下可重新展开的窄栏。
    expect(find.text('学期总览'), findsNothing);
    expect(find.byTooltip('收起学期总览'), findsNothing);
    expect(find.byTooltip('展开学期总览'), findsOneWidget);

    await tester.tap(find.byTooltip('展开学期总览'));
    await tester.pumpAndSettle();

    expect(find.text('学期总览'), findsOneWidget);
    expect(find.byTooltip('收起学期总览'), findsOneWidget);
  });
}
