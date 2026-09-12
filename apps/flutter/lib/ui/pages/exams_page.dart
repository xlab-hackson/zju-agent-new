import 'package:flutter/gestures.dart';
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
  List<Widget> headerExtras(AsyncSnapshot<Json> snapshot) {
    final choices = semesterChoices(rows(snapshot.data?['semesters'] ?? []));
    if (choices.isEmpty) return const [];
    final activeId = choices.any((c) => c.id == semester)
        ? semester
        : choices.first.id;

    return [
      _HorizontalExamSemesterTabs(
        choices: choices,
        selected: activeId,
        onChanged: (val) {
          if (val != semester) {
            setState(() => semester = val);
            syncPageContext();
            refresh(force: false);
          }
        },
      ),
    ];
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

class _HorizontalExamSemesterTabs extends StatefulWidget {
  final List<SemesterChoice> choices;
  final String selected;
  final ValueChanged<String> onChanged;

  const _HorizontalExamSemesterTabs({
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_HorizontalExamSemesterTabs> createState() =>
      _HorizontalExamSemesterTabsState();
}

class _HorizontalExamSemesterTabsState
    extends State<_HorizontalExamSemesterTabs> {
  late final ScrollController _scrollController;
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollToSelected();
  }

  @override
  void didUpdateWidget(covariant _HorizontalExamSemesterTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _scrollToSelected();
    }
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _itemKeys[widget.selected];
      final ctx = key?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.choices.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent &&
              _scrollController.hasClients) {
            final delta = pointerSignal.scrollDelta.dy != 0
                ? pointerSignal.scrollDelta.dy
                : pointerSignal.scrollDelta.dx;
            if (delta != 0) {
              final target = (_scrollController.offset + delta).clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              );
              _scrollController.jumpTo(target);
            }
          }
        },
        child: ScrollConfiguration(
          behavior: const NoScrollbarScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.choices.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _tabItem(widget.choices[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabItem(SemesterChoice choice) {
    final key = _itemKeys.putIfAbsent(choice.id, () => GlobalKey());
    final isSelected = choice.id == widget.selected;
    final displayName = choice.id == 'all' ? '全部学期' : choice.name;

    return InkWell(
      key: key,
      onTap: () {
        if (choice.id != widget.selected) {
          widget.onChanged(choice.id);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? blue.withValues(alpha: .14) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? blue : ink.withValues(alpha: .18),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          displayName,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? blue : ink,
          ),
        ),
      ),
    );
  }
}
