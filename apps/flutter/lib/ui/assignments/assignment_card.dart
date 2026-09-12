import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../../domain/assignment_rules.dart';
import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../shared/ink_tag.dart';
import '../theme.dart';

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({
    super.key,
    required this.assignment,
    required this.now,
    this.urgentHours = 48,
    this.backgroundColor,
    required this.onTap,
  });

  final Json assignment;
  final DateTime now;
  final int urgentHours;
  final Color? backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deadline = deadlineMs(assignment);
    final overdue = deadline != null && deadline <= now.millisecondsSinceEpoch;
    final urgent =
        deadline != null &&
        !overdue &&
        deadline - now.millisecondsSinceEpoch <= urgentHours * 3600 * 1000;
    final status = isSubmitted(assignment)
        ? const InkTag(label: '已提交', color: Color(0xff2e7d32))
        : InkTag(
            label: overdue
                ? '已逾期'
                : urgent
                ? '即将截止'
                : '还不急',
            color: overdue
                ? seal
                : urgent
                ? gold
                : ink,
            dot: urgent,
          );
    return Paper(
      color: backgroundColor,
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(assignment, 'title'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text(assignment, 'courseName'),
                        style: const TextStyle(color: ink, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                status,
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.hourglass_empty, color: gold, size: 15),
                const SizedBox(width: 6),
                Text(
                  '截止：${formatDateTime(text(assignment, 'deadline'))}',
                  style: const TextStyle(fontSize: 12, color: ink),
                ),
                if (rows(assignment['attachments'] ?? []).isNotEmpty) ...[
                  const SizedBox(width: 12),
                  InkTag(
                    label: '附件 ${rows(assignment['attachments'] ?? []).length}',
                    color: ink,
                  ),
                ],
              ],
            ),
            if (text(assignment, 'description').isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                html.parse(text(assignment, 'description')).body?.text ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
