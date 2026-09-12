import 'dart:async';
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
import 'package:zju_campus_agent/domain/course_catalog.dart';
import 'package:zju_campus_agent/domain/formatters.dart';
import 'package:zju_campus_agent/domain/grade_stats.dart';
import 'package:zju_campus_agent/domain/models.dart';
import 'package:zju_campus_agent/ui/dashboard/multi_metric_kpi.dart';
import 'package:zju_campus_agent/ui/pages/feature_page.dart';
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
  group('GradeStats.compute', () {
    test('handles empty grades list gracefully with timetableCredits', () {
      final stats = GradeStats.compute(
        grades: [],
        currentSemester: '2025-2026-1',
        timetableCredits: 16.5,
      );
      expect(stats.hasGrades, isFalse);
      expect(stats.hasData, isFalse);
      expect(stats.gpa, 0.0);
      expect(stats.totalCredits, 0.0);
      expect(stats.totalEarnedCredits, 0.0);
      expect(stats.avgScore, 0.0);
      expect(stats.averageScore, 0.0);
      expect(stats.semesterCredits, 16.5);
    });

    test('computes GPA, earned credits, and average score accurately', () {
      final grades = <Json>[
        {
          'id': '2024-2025-1-CS101',
          'xkkh': '(2024-2025-1)-061B0170-001',
          'semester': '2024-2025-1',
          'courseName': '高级语言程序设计',
          'credit': '4.0',
          'fivePoint': '4.5',
          'original': '92',
          'creditIncluded': true,
          'gpaIncluded': true,
        },
        {
          'id': '2024-2025-1-MATH101',
          'xkkh': '(2024-2025-1)-061B0180-001',
          'semester': '2024-2025-1',
          'courseName': '微积分(甲)I',
          'credit': '5.0',
          'fivePoint': '4.0',
          'original': '85',
          'creditIncluded': true,
          'gpaIncluded': true,
        },
        // 合格制课程（计入学分，不计入 GPA）
        {
          'id': '2024-2025-2-PE101',
          'xkkh': '(2024-2025-2)-061B0190-001',
          'semester': '2024-2025-2',
          'courseName': '体育I',
          'credit': '1.0',
          'fivePoint': '0.0',
          'original': '合格',
          'creditIncluded': true,
          'gpaIncluded': false,
        },
        // 不及格课程（不计入已获得学分）
        {
          'id': '2024-2025-2-PHYS101',
          'xkkh': '(2024-2025-2)-061B0200-001',
          'semester': '2024-2025-2',
          'courseName': '大学物理(甲)I',
          'credit': '4.0',
          'fivePoint': '0.0',
          'original': '55',
          'creditIncluded': true,
          'gpaIncluded': true,
        },
      ];

      final stats = GradeStats.compute(
        grades: grades,
        currentSemester: '2024-2025-1',
      );

      expect(stats.hasGrades, isTrue);
      expect(stats.hasData, isTrue);

      // Earned credits: 4.0 (92) + 5.0 (85) + 1.0 (合格) = 10.0 (55分不及格不计入)
      expect(stats.totalEarnedCredits, 10.0);

      // GPA included courses: CS101 (4.0 * 4.5), MATH101 (5.0 * 4.0), PHYS101 (4.0 * 0.0)
      // Total GPA credits: 4 + 5 + 4 = 13
      // Weighted GPA: (18.0 + 20.0 + 0) / 13 = 38.0 / 13 ≈ 2.923
      final expectedGpa = (4.0 * 4.5 + 5.0 * 4.0 + 4.0 * 0.0) / 13.0;
      expect(stats.gpa, closeTo(expectedGpa, 0.001));

      // Weighted average score: (92 * 4.0 + 85 * 5.0 + 55 * 4.0) / 13.0 = (368 + 425 + 220) / 13 = 1013 / 13 ≈ 77.923
      final expectedAvg = (92.0 * 4.0 + 85.0 * 5.0 + 55.0 * 4.0) / 13.0;
      expect(stats.avgScore, closeTo(expectedAvg, 0.001));

      // Semester credits for 2024-2025-1: 4.0 + 5.0 = 9.0
      expect(stats.semesterCredits, 9.0);
    });

    test(
      'extracts semester credits from xkkh regex even if semester string is empty',
      () {
        final grades = <Json>[
          {
            'id': 'CS201',
            'xkkh': '(2025-2026-1)-061B0170-001',
            'semester': '', // empty from grades('') query
            'courseName': '数据结构',
            'credit': '4.5',
            'original': '待录',
            'creditIncluded': false,
          },
        ];

        final stats = GradeStats.compute(
          grades: grades,
          currentSemester: '2025-2026-1',
        );

        expect(stats.semesterCredits, 4.5);
      },
    );

    test('falls back to course name matching for current semester credits', () {
      final grades = <Json>[
        {
          'courseName': '面向对象程序设计',
          'credit': '3.0',
          'original': '90',
          'creditIncluded': true,
        },
        {
          'courseName': '离散数学',
          'credit': '4.0',
          'original': '88',
          'creditIncluded': true,
        },
      ];

      final stats = GradeStats.compute(
        grades: grades,
        currentSemester: '2025-2026-1',
        currentCourseNames: ['面向对象程序设计', '离散数学', '线性代数'],
      );

      // Found credits for 2 of the 3 courses: 3.0 + 4.0 = 7.0
      expect(stats.semesterCredits, 7.0);
    });

    test(
      'prioritizes authoritative timetableCredits over partial early-released grades in ongoing semester',
      () {
        final grades = <Json>[
          {
            'id': 'SHORT_SEM_01',
            'xkkh': '(2026-2027-1)-061B0010-001',
            'semester': '2026-2027-1',
            'courseName': '短学期实习',
            'credit': '1.5',
            'fivePoint': '4.5',
            'original': '92',
            'creditIncluded': true,
            'gpaIncluded': true,
          },
        ];

        final stats = GradeStats.compute(
          grades: grades,
          currentSemester: '2026-2027-1',
          currentCourseNames: ['短学期实习', '计算机系统概论', '高等数学', '大学物理'],
          timetableCredits: 23.5,
        );

        // timetableCredits (23.5) should be prioritized instead of being shadowed by early-released 1.5 credits!
        expect(stats.semesterCredits, 23.5);
      },
    );
  });

  group('Course overview academic source helpers', () {
    test(
      'dashboard and panel share semester filtering and credit aggregation',
      () {
        final semesters = [
          {'id': '85', 'name': '2026-2027学年秋冬学期'},
          {'id': '2025-2026-2', 'name': '2025-2026学年春夏学期'},
        ];
        final courses = [
          {'name': '线性代数', 'semesterId': '2026-2027-1', 'credit': 3.0},
          {'name': '大学英语', 'semesterId': '85', 'credit': 2.0},
          {'name': '历史课', 'semesterId': '2025-2026-2', 'credit': 2.0},
        ];

        final current = coursesForSemester(courses, semesters, '2026-2027-1');

        expect(
          current.map((course) => course['name']),
          unorderedEquals(['线性代数', '大学英语']),
        );
        expect(courseCredits(current), 5.0);
      },
    );

    test('dataUpdatedLabel uses the shared page timestamp format', () {
      expect(
        dataUpdatedLabel(DateTime.now().toUtc().toIso8601String()),
        startsWith('数据更新于 '),
      );
      expect(dataUpdatedLabel(null), isNull);
    });

    test(
      'CampusService coalesces concurrent requests for one cache key',
      () async {
        final db = AgentDatabase.memory();
        addTearDown(() => db.close());
        final campus = CampusService(CampusSession(_FakeSecrets()), db);
        final gate = Completer<void>();
        var fetches = 0;
        final change = campus.cacheChanges.first;

        Future<List<Json>> fetch() async {
          fetches++;
          await gate.future;
          return [
            {'id': 'shared'},
          ];
        }

        final first = campus.cached('dedupe-test', fetch, refresh: true);
        final second = campus.cached('dedupe-test', fetch, refresh: true);
        await Future<void>.delayed(Duration.zero);

        expect(fetches, 1);
        gate.complete();
        expect(await first, equals(await second));
        expect(await change, 'dedupe-test');
      },
    );
  });

  group('MultiMetricKpi Widget', () {
    testWidgets(
      'renders all 3 metric values and labels without redundant footer',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 136,
                child: MultiMetricKpi(
                  label: '本学期学业',
                  icon: 'book-open',
                  items: [
                    const MultiMetricItem(
                      value: '6',
                      label: '课程数',
                      tooltip: '弹出辅助栏课程总览',
                    ),
                    const MultiMetricItem(
                      value: '18.5',
                      label: '学分数',
                      tooltip: '本学期已选学分',
                    ),
                    const MultiMetricItem(
                      value: '3',
                      label: '考试数',
                      tooltip: '查看考试安排',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(find.text('本学期学业'), findsOneWidget);
        expect(find.text('6'), findsOneWidget);
        expect(find.text('课程数'), findsOneWidget);
        expect(find.text('18.5'), findsOneWidget);
        expect(find.text('学分数'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('考试数'), findsOneWidget);
        // Verify redundant footer is NOT rendered
        expect(find.text('课程 · 学分 · 考试'), findsNothing);
      },
    );

    testWidgets(
      'tapping clickable item triggers onTap while null onTap does not throw',
      (tester) async {
        bool courseTapped = false;
        bool examTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 136,
                child: MultiMetricKpi(
                  label: '本学期学业',
                  icon: 'book-open',
                  items: [
                    MultiMetricItem(
                      value: '6',
                      label: '课程数',
                      onTap: () => courseTapped = true,
                    ),
                    const MultiMetricItem(
                      value: '18.5',
                      label: '学分数',
                      onTap: null, // 学分数不跳转
                    ),
                    MultiMetricItem(
                      value: '3',
                      label: '考试数',
                      onTap: () => examTapped = true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Tap 课程数
        await tester.tap(find.text('课程数'));
        await tester.pumpAndSettle();
        expect(courseTapped, isTrue);

        // Tap 学分数 (should not trigger any callback or error)
        await tester.tap(find.text('学分数'));
        await tester.pumpAndSettle();

        // Tap 考试数
        await tester.tap(find.text('考试数'));
        await tester.pumpAndSettle();
        expect(examTapped, isTrue);
      },
    );

    testWidgets('待办作业 metrics support custom valueColor and independent taps', (
      tester,
    ) async {
      String? tappedTab;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 136,
              child: MultiMetricKpi(
                label: '待办作业',
                icon: 'checklist-paper',
                items: [
                  MultiMetricItem(
                    value: '2',
                    label: '将截止',
                    valueColor: seal,
                    onTap: () => tappedTab = 'urgent',
                  ),
                  MultiMetricItem(
                    value: '5',
                    label: '还不急',
                    onTap: () => tappedTab = 'relaxed',
                  ),
                  MultiMetricItem(
                    value: '8',
                    label: '已提交',
                    valueColor: const Color(0xff2e7d32),
                    onTap: () => tappedTab = 'submitted',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('将截止'), findsOneWidget);
      expect(find.text('还不急'), findsOneWidget);
      expect(find.text('已提交'), findsOneWidget);

      await tester.tap(find.text('将截止'));
      await tester.pumpAndSettle();
      expect(tappedTab, 'urgent');

      await tester.tap(find.text('还不急'));
      await tester.pumpAndSettle();
      expect(tappedTab, 'relaxed');

      await tester.tap(find.text('已提交'));
      await tester.pumpAndSettle();
      expect(tappedTab, 'submitted');
    });

    testWidgets(
      'FeaturePage /exams renders semester tabs instead of dropdown and allows switching',
      (tester) async {
        final db = AgentDatabase.memory();
        final secrets = _FakeSecrets();
        final campus = CampusService(CampusSession(secrets), db);
        final tempDir = Directory.systemTemp.createTempSync('kpi_test_');
        final files = FileService(campus, tempDir);
        final backups = BackupService(db, files);
        final agent = AgentService(campus, files, GuideIndex(const {}));
        final services = AppServices(
          db,
          secrets,
          campus,
          files,
          backups,
          agent,
        );
        services.claimInitialRefresh('/exams');

        await db.put('cache', 'semesters', {
          'items': [
            {'id': '85', 'name': '2026-2027秋冬', 'isActive': true},
            {'id': '84', 'name': '2025-2026春夏', 'isActive': false},
          ],
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
        await db.put('cache', 'exams:2026-2027-1', {
          'items': [
            {
              'id': 'e1',
              'courseName': '大学物理（乙）Ⅱ',
              'time': '2026-11-14T14:00:00+08:00',
              'semester': '2026-2027-1',
            },
          ],
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
        await db.put('cache', 'exams:2025-2026-2', {
          'items': [
            {
              'id': 'e2',
              'courseName': '微积分（甲）Ⅱ',
              'time': '2026-06-20T08:00:00+08:00',
              'semester': '2025-2026-2',
            },
          ],
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeaturePage(services: services, page: '/exams'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify no DropdownButtonFormField is rendered
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.text('全部学期'),
          ),
          findsOneWidget,
        );

        // Verify semester tabs are rendered as pill buttons
        expect(find.text('全部学期'), findsOneWidget);
        expect(find.text('2026-2027秋冬'), findsOneWidget);
        expect(find.text('2025-2026春夏'), findsOneWidget);

        // Initially shows 2026-2027-1 exam
        expect(find.text('大学物理（乙）Ⅱ'), findsOneWidget);

        // Switch to 2025-2026春夏 tab
        await tester.tap(find.text('2025-2026春夏'));
        await tester.pumpAndSettle();

        expect(find.text('微积分（甲）Ⅱ'), findsOneWidget);
      },
    );
  });
}
