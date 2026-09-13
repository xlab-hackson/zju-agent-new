import 'package:flutter/material.dart';

import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../shared/ink_tag.dart';
import '../shared/page_empty.dart';
import '../theme.dart';

class DashboardSchedule extends StatelessWidget {
  const DashboardSchedule({
    super.key,
    required this.events,
    required this.info,
    required this.now,
    required this.onSelectCourse,
  });
  final List<Json> events;
  final Json info;
  final DateTime now;
  final ValueChanged<Json> onSelectCourse;
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Paper(
        child: PageEmpty(
          icon: 'calendar-days',
          title: '${text(info, 'weekString', '四十八小时')} · 四十八小时内暂无日程',
          description: '未来 48 小时内暂无课程或考试安排。',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final event in events)
              SizedBox(
                width: width,
                child: _eventCard(event, isMobile: isMobile),
              ),
          ],
        );
      },
    );
  }

  Widget _eventCard(Json event, {bool isMobile = false}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: paperCard,
      border: Border.all(color: ink.withValues(alpha: .14)),
      borderRadius: BorderRadius.circular(3),
      boxShadow: const [
        BoxShadow(color: Color(0x110e1c38), offset: Offset(2, 3)),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelectCourse(event),
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _eventCardBody(event, isMobile: isMobile),
        ),
      ),
    ),
  );

  Widget _eventCardBody(Json event, {bool isMobile = false}) {
    final isExam = text(event, 'type') == 'exam',
        start = _eventDateTime(event, 'startTime'),
        end = _eventDateTime(event, 'endTime');
    final ongoing =
        start != null &&
        end != null &&
        !now.isBefore(start) &&
        !now.isAfter(end);
    final seconds = ongoing
        ? end.difference(now).inSeconds
        : start == null
        ? 0
        : start.difference(now).inSeconds;
    final total = start == null || end == null
        ? 1
        : end.difference(start).inSeconds.clamp(1, 24 * 3600);
    final progress = ongoing
        ? ((now.difference(start).inSeconds / total) * 100).round().clamp(
            0,
            100,
          )
        : 0;
    final status = ongoing
        ? '正在进行'
        : isExam
        ? '考试'
        : '即将开始';
    final statusColor = ongoing
        ? const Color(0xff2e7d32)
        : isExam
        ? seal
        : blue;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkTag(label: status, color: statusColor, dot: true),
              const Spacer(),
              Text(
                '${text(event, 'date')} ${text(event, 'startTime')}',
                style: const TextStyle(fontSize: 11, color: gold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  text(event, 'title', text(event, 'courseName')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (start != null) ...[
                const SizedBox(width: 8),
                Text(
                  formatHms(seconds),
                  style: TextStyle(
                    color: ongoing ? const Color(0xff2e7d32) : seal,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${text(event, 'location')}  ${text(event, 'teacher')}',
            style: const TextStyle(fontSize: 11, color: ink),
          ),
          if (ongoing) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '课堂进度 $progress%',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xff2e7d32),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    minHeight: 4,
                    color: const Color(0xff2e7d32),
                    backgroundColor: ink.withValues(alpha: .1),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkTag(label: status, color: statusColor, dot: true),
            const Spacer(),
            Text(
              '${text(event, 'date')} ${text(event, 'startTime')}',
              style: const TextStyle(fontSize: 11, color: gold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          text(event, 'title', text(event, 'courseName')),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '${text(event, 'location')}  ${text(event, 'teacher')}',
          style: const TextStyle(fontSize: 12, color: ink),
        ),
        if (start != null) ...[
          const Divider(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ongoing ? '距 离 下 课' : '倒 计 时',
                    style: const TextStyle(fontSize: 10, color: ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    formatHms(seconds),
                    style: TextStyle(
                      color: ongoing ? const Color(0xff2e7d32) : seal,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              if (ongoing) ...[
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '课堂进度 $progress%',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff2e7d32),
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 5,
                        color: const Color(0xff2e7d32),
                        backgroundColor: ink.withValues(alpha: .1),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  DateTime? _eventDateTime(Json event, String field) {
    final date = text(event, 'date'), time = text(event, field);
    if (date.isEmpty || time.isEmpty) return null;
    return DateTime.tryParse('${date}T$time:00+08:00');
  }
}
