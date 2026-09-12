import 'package:flutter/material.dart';

import '../../domain/assignment_rules.dart';
import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../shared/ink_tag.dart';
import '../shared/page_header.dart';
import '../theme.dart';

class ExamSection extends StatelessWidget {
  const ExamSection({
    super.key,
    required this.juan,
    required this.title,
    required this.exams,
    required this.empty,
    required this.now,
  });
  final String juan, title, empty;
  final List<Json> exams;
  final DateTime now;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChapterHead(
          juan: juan,
          title: title,
          trailing: Text(
            '(${exams.length})',
            style: const TextStyle(fontSize: 12, color: ink),
          ),
        ),
        if (exams.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              empty,
              style: const TextStyle(fontSize: 12, color: ink),
            ),
          )
        else
          for (final e in exams) ExamCard(exam: e, now: now),
      ],
    ),
  );
}

class ExamCard extends StatelessWidget {
  const ExamCard({super.key, required this.exam, required this.now});
  final Json exam;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final ts = examMs(exam);
    final badge = ts == null
        ? const InkTag(label: '时间待定', color: ink)
        : ts < now.millisecondsSinceEpoch
        ? const InkTag(label: '已结束', color: ink)
        : _examBadge(ts - now.millisecondsSinceEpoch);
    return Paper(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text(exam, 'courseName'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              badge,
            ],
          ),
          if (text(exam, 'semester').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '学期 ${text(exam, 'semester')}',
                style: const TextStyle(fontSize: 12, color: ink),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: paper.withValues(alpha: .65),
              border: Border.all(color: ink.withValues(alpha: .1)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                ExamValue(
                  label: '考试时间',
                  value: formatDateTime(text(exam, 'time')),
                ),
                ExamValue(label: '地点', value: text(exam, 'location', '待公布')),
                ExamValue(label: '座位', value: text(exam, 'seat', '待公布')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _examBadge(int diff) {
    final hours = diff ~/ 3600000;
    final days = (diff / 86400000).ceil();
    return hours <= 24
        ? InkTag(
            label: '即将开考 · 仅剩 ${hours < 1 ? 1 : hours} 小时',
            color: seal,
            dot: true,
          )
        : days <= 7
        ? InkTag(label: '近期待考 · 距今 $days 天', color: gold)
        : InkTag(label: '待考 · 距今 $days 天', color: blue);
  }
}

class ExamValue extends StatelessWidget {
  const ExamValue({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 165,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: ink)),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}
