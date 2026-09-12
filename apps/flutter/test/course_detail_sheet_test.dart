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
import 'package:zju_campus_agent/ui/pages_v2.dart';
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
  testWidgets('AssignmentCard renders status tag, deadline and triggers onTap',
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
  });

  testWidgets('CourseDetailSheet switches to assignments tab and displays all assignments',
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
        {
          'id': courseId,
          'name': '操作系统',
          'semesterId': '2026-1',
        },
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
          'deadline': now.subtract(const Duration(days: 20)).toIso8601String(),
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
            course: {'id': courseId, 'name': '操作系统'},
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
  });

  testWidgets('AssignmentCard uses custom backgroundColor when provided',
      (tester) async {
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

  testWidgets('PageHead renders title and titleSuffix side by side on narrow screen',
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
    final suffixPos = tester.getTopLeft(find.byKey(const ValueKey('compact-picker')));

    // Both should be on approximately the same vertical line (side-by-side)
    expect((titlePos.dy - suffixPos.dy).abs(), lessThan(30));
    // Suffix must be horizontally to the right of title
    expect(suffixPos.dx, greaterThan(titlePos.dx));
  });

  test('semesterChoices respects includeAll parameter', () {
    final raw = [
      {'id': '2025-2026-1', 'name': '2025-2026秋冬'},
    ];
    final withAll = semesterChoices(raw, includeAll: true);
    expect(withAll.any((c) => c.id == 'all'), isTrue);

    final withoutAll = semesterChoices(raw, includeAll: false);
    expect(withoutAll.any((c) => c.id == 'all'), isFalse);
  });

  testWidgets('CourseRightPanel filters courses by selected semester',
      (tester) async {
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
              data: {
                'semesters': semesters,
                'courses': courses,
              },
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

    // Open dropdown and switch to '2024-2025-2'
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2024-2025春夏').last);
    await tester.pumpAndSettle();

    // Now only 1 course in 2024-2025春夏
    expect(find.text('2024-2025春夏 1 门'), findsOneWidget);
    expect(find.text('计算机网络'), findsOneWidget);
    expect(find.text('编译原理'), findsNothing);
    expect(find.text('操作系统'), findsNothing);
  });

  testWidgets('Timetable and right panel semesters are decoupled in FeaturePage',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final db = AgentDatabase.memory();
    addTearDown(() => db.close());
    final secrets = _FakeSecrets();
    final campus = CampusService(CampusSession(secrets), db);
    final tempDir =
        Directory.systemTemp.createTempSync('course_decouple_test_');
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
  });

  testWidgets('Desktop courses header switches semester via tabs',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final db = AgentDatabase.memory();
    addTearDown(() => db.close());
    final secrets = _FakeSecrets();
    final campus = CampusService(CampusSession(secrets), db);
    final tempDir =
        Directory.systemTemp.createTempSync('course_tabs_test_');
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

  testWidgets('CourseRightPanel provides dedicated refresh button',
      (tester) async {
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

    // Switch tab
    await tester.tap(find.text('2025-2026春夏'));
    expect(switchedSemester, '2025-2026-2');

    // Click export & refresh
    await tester.tap(find.text('导出图片'));
    expect(exportedPng, isTrue);
    await tester.tap(find.byTooltip('刷新课表'));
    expect(refreshed, isTrue);
  });

  testWidgets(
      'TimetableView renders centered title when isExporting',
      (tester) async {
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

    // When exporting, renders centered title for clean screenshot
    expect(find.text('浙江大学课程表（2025-2026-1）'), findsOneWidget);
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
  });

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
  });
}
