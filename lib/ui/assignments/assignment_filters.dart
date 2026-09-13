import 'package:flutter/material.dart';

import '../../domain/assignment_rules.dart';
import '../../domain/models.dart';
import '../shared/side_section.dart';
import '../theme.dart';

class AssignmentRightPanel extends StatelessWidget {
  const AssignmentRightPanel({
    super.key,
    required this.data,
    required this.hours,
    required this.onHoursChanged,
  });
  final Json data;
  final int hours;
  final ValueChanged<int> onHoursChanged;

  @override
  Widget build(BuildContext context) {
    final rawAll = rows(data['items']);
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = rawAll.where((a) => isVisibleAssignment(a, now)).toList();
    final threshold = now + hours * 3600 * 1000;
    final urgent = all
        .where(
          (a) =>
              a['submitted'] != true &&
              deadlineMs(a) != null &&
              deadlineMs(a)! > now &&
              deadlineMs(a)! <= threshold,
        )
        .length;
    final relaxed = all
        .where(
          (a) =>
              a['submitted'] != true &&
              (deadlineMs(a) == null || deadlineMs(a)! > threshold),
        )
        .length;
    final overdue = all
        .where(
          (a) =>
              a['submitted'] != true &&
              deadlineMs(a) != null &&
              deadlineMs(a)! <= now,
        )
        .length;
    final submitted = all.where(isSubmitted).length;
    return SideSection(
      title: '分类设置',
      icon: 'cartoon-settings',
      children: [
        const Text(
          '将截止阈值',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Slider(
          value: hours.toDouble(),
          min: 1,
          max: 72,
          divisions: 71,
          onChanged: (v) => onHoursChanged(v.round()),
        ),
        Center(
          child: Text(
            '距截止 ≤ $hours 小时',
            style: const TextStyle(fontSize: 11, color: gold),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: paper.withValues(alpha: .7),
            border: Border.all(color: ink.withValues(alpha: .1)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            children: [
              SideCount(
                label: '将截止',
                value: urgent,
                color: seal,
                icon: Icons.notifications_none,
              ),
              SideCount(
                label: '还不急',
                value: relaxed,
                color: gold,
                icon: Icons.hourglass_empty,
              ),
              SideCount(
                label: '近期截止',
                value: overdue,
                color: ink,
                icon: Icons.description_outlined,
              ),
              SideCount(
                label: '已提交',
                value: submitted,
                color: const Color(0xff2e7d32),
                icon: Icons.checklist,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
