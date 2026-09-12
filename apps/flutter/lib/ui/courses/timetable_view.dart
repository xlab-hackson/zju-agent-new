import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../domain/course_catalog.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../domain/timetable_options.dart';
import '../export.dart';
import '../shared/page_empty.dart';
import '../theme.dart';

class TimetableView extends StatefulWidget {
  const TimetableView({
    super.key,
    required this.entries,
    required this.semester,
    this.wide = false,
    this.choices = const [],
    this.refreshing = false,
    this.isExporting = false,
    this.onSemesterChanged,
    this.onExportPng,
    this.onExportXlsx,
    this.onRefresh,
    this.onSelectCourse,
  });
  final List<TimetableEntry> entries;
  final String semester;
  final bool wide;
  final List<SemesterChoice> choices;
  final bool refreshing;
  final bool isExporting;
  final ValueChanged<String>? onSemesterChanged;
  final VoidCallback? onExportPng;
  final VoidCallback? onExportXlsx;
  final VoidCallback? onRefresh;
  final ValueChanged<TimetableEntry>? onSelectCourse;

  @override
  State<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends State<TimetableView> {
  String _selectedSubSemester = '';

  @override
  void initState() {
    super.initState();
    final active = widget.entries.where((e) => e.selected).toList();
    final choices = getSubSemesterChoices(widget.semester, active);
    _selectedSubSemester = choices.isNotEmpty ? choices.first.id : '';
  }

  @override
  void didUpdateWidget(TimetableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.semester != widget.semester) {
      final active = widget.entries.where((e) => e.selected).toList();
      final choices = getSubSemesterChoices(widget.semester, active);
      _selectedSubSemester = choices.isNotEmpty ? choices.first.id : '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeEntries = widget.entries.where((e) => e.selected).toList();
    final subChoices = getSubSemesterChoices(widget.semester, activeEntries);
    final effectiveSub = subChoices.any((c) => c.id == _selectedSubSemester)
        ? _selectedSubSemester
        : (subChoices.isNotEmpty ? subChoices.first.id : '');
    final filtered = filterTimetableBySubSemester(activeEntries, effectiveSub);
    final merged = mergeTimetable(filtered);
    final courses = merged.map((e) => e.courseName).toSet().toList();
    final showHeader = !widget.isExporting;
    final isMobile = !widget.wide;
    final sessionColWidth = isMobile ? 30.0 : 52.0;

    String subTitleSuffix() {
      if (effectiveSub.isEmpty) return '';
      final choice = subChoices.firstWhere(
        (c) => c.id == effectiveSub,
        orElse: () =>
            SubSemesterChoice(id: effectiveSub, name: '$effectiveSub学期'),
      );
      return ' - ${choice.name}';
    }

    return Container(
      width: double.infinity,
      color: paperCard,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            _header(context)
          else
            Center(
              child: Text(
                '浙江大学课程表（${widget.semester}${subTitleSuffix()}）',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(height: 10),
          if (subChoices.length > 1) ...[
            _subSemesterBar(subChoices, effectiveSub, isMobile),
            const SizedBox(height: 10),
          ],
          if (activeEntries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: PageEmpty(icon: 'calendar-grid', title: '该学期暂无课表数据'),
            )
          else if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: PageEmpty(icon: 'calendar-grid', title: '该分段暂无课程安排'),
            )
          else ...[
            _gridHeader(isMobile, sessionColWidth),
            SizedBox(
              height: 13 * 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: sessionColWidth,
                    child: Column(
                      children: [
                        for (var i = 1; i <= 13; i++)
                          _sectionLabel(i, isMobile),
                      ],
                    ),
                  ),
                  for (var day = 1; day <= 7; day++)
                    Expanded(child: _dayColumn(day, merged, courses, isMobile)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subSemesterBar(
    List<SubSemesterChoice> choices,
    String activeId,
    bool compact,
  ) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '学期分段：',
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            color: ink.withValues(alpha: .68),
            fontWeight: FontWeight.w500,
          ),
        ),
        for (var i = 0; i < choices.length; i++) ...[
          if (i > 0) SizedBox(width: compact ? 6 : 8),
          _subSemesterButton(choices[i], activeId, compact),
        ],
      ],
    ),
  );

  Widget _subSemesterButton(
    SubSemesterChoice choice,
    String activeId,
    bool compact,
  ) {
    final isSelected = choice.id == activeId;
    return InkWell(
      onTap: () {
        if (choice.id != _selectedSubSemester) {
          setState(() {
            _selectedSubSemester = choice.id;
          });
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: isSelected ? blue : blue.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? blue : blue.withValues(alpha: .22),
            width: 1,
          ),
        ),
        child: Text(
          choice.name,
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? paperCard : ink,
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compactActions = constraints.maxWidth < 700;
      final tabAreaWidth = compactActions
          ? math.max(120.0, constraints.maxWidth - 120)
          : math.min(constraints.maxWidth * 0.5, constraints.maxWidth - 340.0);

      final count = widget.choices.length;
      final spacing = count > 4 ? 4.0 : 6.0;

      double estimatedNaturalWidth = 0.0;
      for (final c in widget.choices) {
        double tabW = 32.0;
        for (final char in c.name.runes) {
          tabW += (char >= 0x2e80 && char <= 0x9fff) ? 16.0 : 12.0;
        }
        estimatedNaturalWidth += math.max(160.0, tabW);
      }
      estimatedNaturalWidth += math.max(0, count - 1) * spacing;

      final needAdaptive =
          !compactActions && (estimatedNaturalWidth > tabAreaWidth);

      Widget tabsWidget;
      if (compactActions) {
        tabsWidget = ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (final choice in widget.choices) ...[
                  _semesterTab(choice, compact: true),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        );
      } else if (needAdaptive) {
        final widthPerTab =
            (tabAreaWidth - math.max(0, count - 1) * spacing) / count;
        tabsWidget = SizedBox(
          width: tabAreaWidth,
          child: Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) SizedBox(width: spacing),
                Expanded(
                  child: _adaptiveSemesterTab(
                    widget.choices[i],
                    availableWidth: widthPerTab,
                  ),
                ),
              ],
            ],
          ),
        );
      } else {
        tabsWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _semesterTab(widget.choices[i], compact: false),
            ],
          ],
        );
      }

      final actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compactActions) ...[
            IconButton(
              onPressed: widget.entries.isEmpty ? null : widget.onExportPng,
              tooltip: '导出图片',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.image_outlined, size: 18),
            ),
            IconButton(
              onPressed: widget.entries.isEmpty ? null : widget.onExportXlsx,
              tooltip: '导出 Excel',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.table_chart_outlined, size: 18),
            ),
            IconButton(
              onPressed: widget.refreshing ? null : widget.onRefresh,
              tooltip: '刷新课表',
              visualDensity: VisualDensity.compact,
              icon: widget.refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 18),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: widget.entries.isEmpty ? null : widget.onExportPng,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: const Text('导出图片'),
              style: TextButton.styleFrom(
                foregroundColor: ink,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: widget.entries.isEmpty ? null : widget.onExportXlsx,
              icon: const Icon(Icons.table_chart_outlined, size: 16),
              label: const Text('导出 Excel'),
              style: TextButton.styleFrom(
                foregroundColor: ink,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: widget.refreshing ? null : widget.onRefresh,
              tooltip: '刷新课表',
              icon: widget.refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: blue,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 18),
            ),
          ],
        ],
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (compactActions)
            Expanded(child: tabsWidget)
          else ...[
            tabsWidget,
            const Spacer(),
          ],
          actions,
        ],
      );
    },
  );

  Widget _adaptiveSemesterTab(
    SemesterChoice choice, {
    required double availableWidth,
  }) {
    final isSelected = choice.id == widget.semester;
    final horizontalPad = availableWidth < 70
        ? 2.0
        : (availableWidth < 90 ? 4.0 : 6.0);
    final fontSize = availableWidth < 70
        ? 10.5
        : (availableWidth < 90 ? 11.0 : 12.0);

    return InkWell(
      onTap: () {
        if (choice.id != widget.semester) {
          widget.onSemesterChanged?.call(choice.id);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? blue.withValues(alpha: .14) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? blue : ink.withValues(alpha: .18),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            choice.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? blue : ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _semesterTab(SemesterChoice choice, {bool compact = false}) {
    final isSelected = choice.id == widget.semester;
    return InkWell(
      onTap: () {
        if (choice.id != widget.semester) {
          widget.onSemesterChanged?.call(choice.id);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 5 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? blue.withValues(alpha: .14) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? blue : ink.withValues(alpha: .18),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            choice.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? blue : ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _gridHeader(bool isMobile, double sessionColWidth) => Row(
    children: [
      SizedBox(
        width: sessionColWidth,
        child: Text(
          isMobile ? '节次\n时间' : '节次\n上课时间',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: isMobile ? 8 : 10, color: ink),
        ),
      ),
      for (final day in dayNames)
        Expanded(
          child: Center(
            child: Text(
              '周$day',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 10.5 : 12,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _sectionLabel(int i, bool isMobile) => SizedBox(
    height: 52,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$i',
          style: TextStyle(
            fontSize: isMobile ? 9.5 : 11,
            fontWeight: FontWeight.bold,
            color: blue,
          ),
        ),
        Text(
          '${sessionTimes[i][0]}\n${sessionTimes[i][1]}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isMobile ? 6.8 : 8,
            color: ink,
            height: 1.1,
          ),
        ),
      ],
    ),
  );

  static String _formatCourseName(String name, {required bool isMobile}) {
    if (!isMobile) return name;
    final cleaned = name.replaceAll('\n', '').trim();
    final chars = cleaned.characters.toList();
    if (chars.isEmpty) return name;

    // 移动端保证一行显示 3 个字，最多 3 行（最多 8 个字再省略），杜绝 4-3-1 等怪异换行
    final line1 = chars.take(3).join();
    if (chars.length <= 3) return line1;

    final line2 = chars.skip(3).take(3).join();
    if (chars.length <= 6) return '$line1\n$line2';

    if (chars.length <= 8) {
      final line3 = chars.skip(6).take(2).join();
      return '$line1\n$line2\n$line3';
    } else {
      final line3 = '${chars.skip(6).take(2).join()}...';
      return '$line1\n$line2\n$line3';
    }
  }

  Widget _dayColumn(
    int day,
    List<TimetableEntry> entries,
    List<String> courses,
    bool isMobile,
  ) => Stack(
    children: [
      const SizedBox(height: 13 * 52),
      for (final e in entries.where(
        (e) => e.weekday == day && e.startSection <= 13,
      ))
        Positioned(
          top: (e.startSection - 1) * 52 + 2,
          left: isMobile ? 1 : 2,
          right: isMobile ? 1 : 2,
          height:
              ((e.endSection.clamp(e.startSection, 13) - e.startSection + 1) *
                          52 -
                      4)
                  .toDouble(),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onSelectCourse != null
                  ? () => widget.onSelectCourse!(e)
                  : null,
              borderRadius: BorderRadius.circular(3),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 2 : 5,
                  vertical: isMobile ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: Color(
                    courseColors[courses.indexOf(e.courseName) %
                        courseColors.length],
                  ),
                  border: Border(
                    left: BorderSide(
                      color: blue.withValues(alpha: .55),
                      width: isMobile ? 1.5 : 2,
                    ),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatCourseName(e.courseName, isMobile: isMobile),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 8.5 : 10,
                          fontWeight: FontWeight.bold,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${e.teacher}\n${e.location}\n${e.subSemester.isNotEmpty ? '${e.subSemester} ' : ''}${e.weeks.isEmpty ? '' : '${compressWeeks(e.weeks)} 周'}',
                        style: TextStyle(
                          fontSize: isMobile ? 7 : 8,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
