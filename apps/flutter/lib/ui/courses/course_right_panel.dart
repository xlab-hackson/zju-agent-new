import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/course_catalog.dart';
import '../../domain/formatters.dart';
import '../../domain/grade_stats.dart';
import '../../domain/models.dart';
import '../shared/page_empty.dart';
import '../shared/side_section.dart';
import '../theme.dart';

class CourseRightPanel extends StatelessWidget {
  const CourseRightPanel({
    super.key,
    required this.data,
    required this.selected,
    required this.onChanged,
    required this.onSelect,
    this.onRefresh,
    this.refreshing = false,
  });
  final Json data;
  final String selected;
  final ValueChanged<String> onChanged;
  final ValueChanged<Json> onSelect;
  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final choices = semesterChoices(rows(data['semesters'] ?? []));
    final semesterNames = <String, String>{
      for (final choice in choices) choice.id: choice.name,
    };
    for (final raw in rows(data['semesters'] ?? [])) {
      final rawId = text(raw, 'id'), name = text(raw, 'name');
      if (rawId.isNotEmpty) {
        semesterNames[rawId] = semesterDisplay(rawId, name);
      }
    }
    final allCourses = rows(data['courses']);
    final allGrades = rows(data['grades'] ?? []);
    final semesters = rows(data['semesters'] ?? []);
    final matchingIds = matchingSemesterIds(semesters, selected);
    final courses = coursesForSemester(allCourses, semesters, selected);
    final groups = <String, List<Json>>{};
    for (final c in courses) {
      final key = text(c, 'semesterId').trim().isNotEmpty
          ? text(c, 'semesterId').trim()
          : text(c, 'semester').trim();
      groups.putIfAbsent(key, () => []).add(c);
    }
    final selectedCourses = courses.where(_isSelected).toList();
    final panelStats = computeSemesterGradeStats(
      selected: selected,
      courses: selectedCourses,
      allCourses: allCourses.where(_isSelected).toList(),
      allGrades: allGrades,
      matchingIds: matchingIds,
    );
    final updatedLabel = dataUpdatedLabel(text(data, '_updatedAt'));
    final sortedGroupEntries = groups.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return SideSection(
      title: '学期总览',
      icon: 'scroll',
      trailing: onRefresh != null
          ? IconButton(
              onPressed: refreshing ? null : onRefresh,
              tooltip: '刷新课程',
              icon: refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 16, color: ink),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            )
          : null,
      children: [
        Row(
          children: [
            const Text(
              '学期',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              selected == 'all'
                  ? '全部课程 ${courses.length} 门'
                  : '${semesterNames[selected] ?? selected} ${courses.length} 门',
              style: const TextStyle(fontSize: 11, color: ink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _HorizontalSemesterTabs(
          choices: choices,
          selected: selected,
          onChanged: onChanged,
        ),
        if (updatedLabel != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              updatedLabel,
              style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .5)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildStatsCard(context, panelStats),
        if (groups.isEmpty)
          const PageEmpty(title: '该学期暂无课程记录')
        else
          for (final group in sortedGroupEntries) ...[
            Text(
              '${semesterNames[group.key] ?? group.key}  ${group.value.length} 门',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            for (final course
                in (group.value
                  ..sort((a, b) {
                    final aSelected = _isSelected(a);
                    final bSelected = _isSelected(b);
                    if (aSelected != bSelected) {
                      return aSelected ? -1 : 1;
                    }
                    final aCreated = _isCreated(a);
                    final bCreated = _isCreated(b);
                    if (aCreated != bCreated) {
                      return aCreated ? -1 : 1;
                    }
                    return text(a, 'name').compareTo(text(b, 'name'));
                  })))
              _buildCourseItem(course),
          ],
      ],
    );
  }

  static bool _isSelected(Json course) => isCourseSelected(course);

  static bool _isCreated(Json course) =>
      course['learningZjuCreated'] == true ||
      (course['learningZjuCreated'] != false &&
          text(course, 'id').isNotEmpty &&
          !text(course, 'id').startsWith('(') &&
          int.tryParse(text(course, 'id')) != null);

  Widget _buildCourseItem(Json course) {
    final teacher = text(course, 'teacher', text(course, 'jsxm')).trim();
    final creditVal = double.tryParse('${course['credit']}') ?? 0.0;
    final score = text(course, 'score', text(course, 'original')).trim();
    final gpa = text(course, 'gpa', text(course, 'fivePoint')).trim();
    final gradeBadge = formatGradeBadge(score, gpa);
    final isSelected = _isSelected(course);
    final isLearningCreated = _isCreated(course);
    final isEnrolledAndCreated = isSelected && isLearningCreated;
    final statusBadge =
        !isSelected ? '未选中' : (!isLearningCreated ? '未建课' : '');

    final scheduleTime = text(course, 'scheduleTime').trim();
    final teachingClassName = text(course, 'teachingClassName').trim();
    final fallbackTime = text(course, 'time').trim();
    final timeStr = scheduleTime.isNotEmpty
        ? scheduleTime
        : (fallbackTime.isNotEmpty ? fallbackTime : teachingClassName);

    final borderColor = isEnrolledAndCreated
        ? gold.withValues(alpha: .55)
        : ink.withValues(alpha: .14);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        decoration: BoxDecoration(
          color: paperCard,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0a0e1c38),
              offset: Offset(0, 1),
              blurRadius: 1,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => onSelect(course),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          text(course, 'name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: ink,
                          ),
                        ),
                      ),
                      if (statusBadge.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: ink.withValues(alpha: .2),
                            ),
                          ),
                          child: Text(
                            statusBadge,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: ink.withValues(alpha: .65),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (gradeBadge.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: seal.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: seal.withValues(alpha: .2)),
                          ),
                          child: Text(
                            gradeBadge,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: seal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (teacher.isNotEmpty || creditVal > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          if (teacher.isNotEmpty) ...[
                            Icon(
                              Icons.person_outline,
                              size: 11,
                              color: isEnrolledAndCreated
                                  ? ink
                                  : ink.withValues(alpha: .5),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                teacher,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isEnrolledAndCreated
                                      ? ink
                                      : ink.withValues(alpha: .5),
                                ),
                              ),
                            ),
                          ] else
                            const Spacer(),
                          if (creditVal > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: ink.withValues(alpha: .06),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${creditVal.toStringAsFixed(creditVal.truncateToDouble() == creditVal ? 0 : 1)} 学分',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isEnrolledAndCreated
                                      ? ink
                                      : ink.withValues(alpha: .6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (timeStr.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        timeStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: isEnrolledAndCreated
                              ? ink
                              : ink.withValues(alpha: .5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  static String _formatCredit(double cr) {
    if (cr <= 0) return '0';
    return cr == cr.roundToDouble()
        ? cr.toInt().toString()
        : cr.toStringAsFixed(1);
  }

  Widget _buildStatsCard(BuildContext context, SemesterGradeStats stats) {
    final gpaText = stats.hasGrades && stats.gpa > 0
        ? stats.gpa.toStringAsFixed(2)
        : (stats.totalCourses > 0 && stats.gradedCourses == 0 ? '修读中' : '--');

    final creditText = stats.hasGrades
        ? (stats.selected == 'all'
              ? _formatCredit(stats.earnedCredits)
              : (stats.enrolledCredits > 0
                    ? '${_formatCredit(stats.earnedCredits)} / ${_formatCredit(stats.enrolledCredits)}'
                    : _formatCredit(stats.earnedCredits)))
        : (stats.enrolledCredits > 0
              ? _formatCredit(stats.enrolledCredits)
              : '--');

    final scoreText = stats.hasGrades && stats.avgScore > 0
        ? stats.avgScore.toStringAsFixed(1)
        : '--';

    final gpaLabel = stats.selected == 'all' ? '目前总绩点' : '学期绩点';
    final creditLabel = stats.selected == 'all'
        ? '获得总学分'
        : (stats.hasGrades ? '获得/已选学分' : '已选学分');
    final scoreLabel = stats.selected == 'all' ? '百分制均分' : '学期百分制';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ink.withValues(alpha: .12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatMetric(
                value: gpaText,
                label: gpaLabel,
                isHighlight: stats.hasGrades,
              ),
              Container(
                width: 1,
                height: 26,
                color: ink.withValues(alpha: .08),
              ),
              _buildStatMetric(value: creditText, label: creditLabel),
              Container(
                width: 1,
                height: 26,
                color: ink.withValues(alpha: .08),
              ),
              _buildStatMetric(value: scoreText, label: scoreLabel),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            stats.selected == 'all'
                ? '全历程共 ${stats.totalCourses} 门课程 · 已出分 ${stats.gradedCourses} 门'
                : '本学期共 ${stats.totalCourses} 门课程 · ${stats.gradedCourses > 0 ? "已出分 ${stats.gradedCourses} 门" : "暂未出分"}',
            style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .5)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMetric({
    required String value,
    required String label,
    bool isHighlight = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isHighlight ? seal : ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: ink.withValues(alpha: .6)),
          ),
        ],
      ),
    );
  }
}

class _HorizontalSemesterTabs extends StatefulWidget {
  final List<SemesterChoice> choices;
  final String selected;
  final ValueChanged<String> onChanged;

  const _HorizontalSemesterTabs({
    required this.choices,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_HorizontalSemesterTabs> createState() => _HorizontalSemesterTabsState();
}

class _HorizontalSemesterTabsState extends State<_HorizontalSemesterTabs> {
  late final ScrollController _scrollController;
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollToSelected();
  }

  @override
  void didUpdateWidget(covariant _HorizontalSemesterTabs oldWidget) {
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

    return Listener(
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
        behavior: ScrollConfiguration.of(context).copyWith(
          scrollbars: false,
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
