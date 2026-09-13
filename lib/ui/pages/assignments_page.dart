import 'package:flutter/material.dart';

import '../../application/page_loaders/assignments_loader.dart';
import '../../domain/assignment_rules.dart';
import '../../domain/models.dart';
import '../assignments/assignment_card.dart';
import '../assignments/assignment_filters.dart';
import '../shared/campus_page.dart';
import '../shared/file_actions.dart';
import '../shared/page_empty.dart';
import '../theme.dart';

class AssignmentsPage extends CampusDataPage {
  const AssignmentsPage({
    super.key,
    required super.services,
    this.initialAssignmentTab,
  });
  final String? initialAssignmentTab;
  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends CampusPageState<AssignmentsPage>
    with FileActions<AssignmentsPage> {
  @override
  String get pageKey => '/assignments';
  @override
  String get title => '待办作业';

  String assignmentTab = 'all';
  int urgentHours = 24;
  @override
  bool get needsSecondTicker => true;
  @override
  Future<Json> load({bool refresh = false}) =>
      loadAssignmentsPage(s, refresh: refresh);
  @override
  bool usesCache(String key) =>
      key == 'courses' || key.startsWith('assignments:');
  @override
  PageContext buildPageContext({Json? activeCourse, String? courseTab}) =>
      PageContext.assignments(tab: assignmentTab, urgentHours: urgentHours);
  @override
  void initializePage() {
    final initialTab =
        widget.initialAssignmentTab ??
        (s.targetAssignmentTab != 'all' ? s.targetAssignmentTab : null);
    if (initialTab != null && initialTab.isNotEmpty) {
      assignmentTab = initialTab;
      s.targetAssignmentTab = 'all';
    }
  }

  @override
  void didUpdateWidget(AssignmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetTab =
        widget.initialAssignmentTab ??
        (s.targetAssignmentTab != 'all' ? s.targetAssignmentTab : null);
    if (targetTab != null &&
        targetTab.isNotEmpty &&
        assignmentTab != targetTab) {
      setState(() {
        assignmentTab = targetTab;
        s.targetAssignmentTab = 'all';
      });
      syncPageContext();
    }
  }

  @override
  List<Widget> headerExtras(AsyncSnapshot<Json> snapshot) => [
    if (snapshot.hasData)
      Paper(
        child: AssignmentRightPanel(
          data: snapshot.data!,
          hours: urgentHours,
          onHoursChanged: (value) {
            setState(() => urgentHours = value);
            syncPageContext();
          },
        ),
      ),
  ];
  @override
  List<Widget> content(Json d, {required bool wide}) {
    final rawAll = rows(d['items']);
    final nowMs = now.millisecondsSinceEpoch;
    final threshold = nowMs + urgentHours * 3600 * 1000;

    // 未到截止时间的全部显示，截止时间已过，但是未超过一周的也显示，已经截止超过一周的就不显示了
    final all = rawAll.where((a) => isVisibleAssignment(a, nowMs)).toList();

    // 排序：未提交未到期的排在前面（按截止时间由近及远），未提交且已逾期（7天内）的排其后，已提交的排最后
    all.sort(compareAssignments);

    final overdue = all
        .where(
          (a) =>
              !isSubmitted(a) &&
              deadlineMs(a) != null &&
              deadlineMs(a)! <= nowMs,
        )
        .toList();
    final urgent = all
        .where(
          (a) =>
              !isSubmitted(a) &&
              deadlineMs(a) != null &&
              deadlineMs(a)! > nowMs &&
              deadlineMs(a)! <= threshold,
        )
        .toList();
    final relaxed = all
        .where(
          (a) =>
              !isSubmitted(a) &&
              (deadlineMs(a) == null || deadlineMs(a)! > threshold),
        )
        .toList();
    final submitted = all.where(isSubmitted).toList();
    final selected = switch (assignmentTab) {
      'urgent' => urgent,
      'relaxed' => relaxed,
      'overdue' => overdue,
      'submitted' => submitted,
      _ => all,
    };
    final tabs = [
      ('all', '全部', all.length, blue),
      ('urgent', '将截止', urgent.length, seal),
      ('relaxed', '还不急', relaxed.length, gold),
      ('overdue', '近期截止', overdue.length, ink),
      ('submitted', '已提交', submitted.length, const Color(0xff2e7d32)),
    ];
    return [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${tab.$2}  ${tab.$3}'),
                  selected: assignmentTab == tab.$1,
                  selectedColor: tab.$4.withValues(alpha: .16),
                  onSelected: (_) {
                    setState(() => assignmentTab = tab.$1);
                    syncPageContext();
                  },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (selected.isEmpty)
        Paper(
          child: PageEmpty(
            icon: 'checklist-paper',
            title: switch (assignmentTab) {
              'urgent' => '暂无紧急作业',
              'relaxed' => '暂无常规作业',
              'overdue' => '暂无近期截止作业',
              'submitted' => '暂无已提交作业',
              _ => '暂无待办作业',
            },
            description: '当前分类下没有相关作业记录。',
          ),
        )
      else
        for (final assignment in selected) _assignmentCard(assignment),
    ];
  }

  Widget _assignmentCard(Json a) => AssignmentCard(
    assignment: a,
    now: now,
    urgentHours: urgentHours,
    onTap: () => assignmentDetail(a),
  );
}
