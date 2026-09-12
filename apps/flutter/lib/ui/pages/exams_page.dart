import 'package:flutter/material.dart';

import '../../application/page_loaders/exams_loader.dart';
import '../../domain/assignment_rules.dart';
import '../../domain/course_catalog.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../exams/exam_card.dart';
import '../shared/campus_page.dart';
import '../theme.dart';

class ExamsPage extends CampusDataPage {
  const ExamsPage({super.key, required super.services});
  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends CampusPageState<ExamsPage> {
  @override
  String get pageKey => '/exams';
  @override
  String get title => '考试安排';

  String semester = academicSemester(beijing(DateTime.now()));
  @override
  bool get needsSecondTicker => true;
  @override
  Future<Json> load({bool refresh = false}) =>
      loadExamsPage(s, semester, refresh: refresh);
  @override
  bool usesCache(String key) => key == 'semesters' || key.startsWith('exams:');
  @override
  PageContext buildPageContext({Json? activeCourse, String? courseTab}) =>
      PageContext.exams(semester: semester);
  @override
  List<Widget> headerExtras(AsyncSnapshot<Json> snapshot) => [
    _semesterPicker(semesterChoices(rows(snapshot.data?['semesters'] ?? []))),
  ];
  Widget _semesterPicker(List<SemesterChoice> choices) {
    if (choices.isEmpty) return const SizedBox.shrink();
    final activeId = choices.any((c) => c.id == semester)
        ? semester
        : choices.first.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final choice in choices)
                _examSemesterTab(choice, isSelected: choice.id == activeId),
            ],
          );
        },
      ),
    );
  }

  Widget _examSemesterTab(SemesterChoice choice, {required bool isSelected}) {
    return InkWell(
      onTap: () {
        if (choice.id != semester) {
          setState(() => semester = choice.id);
          syncPageContext();
          refresh(force: false);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? blue : paperCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? blue : ink.withValues(alpha: .2),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: blue.withValues(alpha: .2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          choice.id == 'all' ? '全部学期' : choice.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? paperCard : ink,
          ),
        ),
      ),
    );
  }

  @override
  List<Widget> content(Json d, {required bool wide}) {
    final all = rows(d['items']);
    final upcoming =
        all
            .where(
              (e) =>
                  examMs(e) != null && examMs(e)! >= now.millisecondsSinceEpoch,
            )
            .toList()
          ..sort((a, b) => (examMs(a) ?? 0).compareTo(examMs(b) ?? 0));
    final past =
        all
            .where(
              (e) =>
                  examMs(e) != null && examMs(e)! < now.millisecondsSinceEpoch,
            )
            .toList()
          ..sort((a, b) => (examMs(b) ?? 0).compareTo(examMs(a) ?? 0));
    final noTime = all.where((e) => examMs(e) == null).toList();
    return [
      ExamSection(
        juan: '壹',
        title: '待考科目',
        exams: upcoming,
        empty: '本学期暂无待考科目安排',
        now: now,
      ),
      ExamSection(
        juan: '贰',
        title: '已结束',
        exams: past,
        empty: '无已结束的考试',
        now: now,
      ),
      ExamSection(
        juan: '叁',
        title: '待安排时间',
        exams: noTime,
        empty: '无待安排的考试',
        now: now,
      ),
    ];
  }
}
