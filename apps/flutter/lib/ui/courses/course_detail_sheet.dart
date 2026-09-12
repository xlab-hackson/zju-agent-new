import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:html/parser.dart' as html;

import '../../application/services.dart';
import '../../domain/assignment_rules.dart';
import '../../domain/course_catalog.dart';
import '../../domain/formatters.dart';
import '../../domain/models.dart';
import '../assignments/assignment_card.dart';
import '../shared/page_empty.dart';
import '../theme.dart';

class CourseDetailSheet extends StatefulWidget {
  const CourseDetailSheet({
    super.key,
    required this.services,
    required this.course,
    required this.onDownload,
    required this.onPreview,
    this.onAssignmentDetail,
    this.onTabChanged,
  });
  final AppServices services;
  final Json course;
  final Future<void> Function(Json) onDownload;
  final Future<void> Function(Json) onPreview;
  final void Function(Json)? onAssignmentDetail;
  final ValueChanged<String>? onTabChanged;

  @override
  State<CourseDetailSheet> createState() => _CourseDetailSheetState();
}

class _CourseDetailSheetState extends State<CourseDetailSheet> {
  late Future<List<Json>> materials;
  late Future<List<Json>> assignments;
  final busyFileIds = <String>{};
  String currentTab = 'materials';

  Future<void> runFileAction(
    Json file,
    Future<void> Function(Json) action,
  ) async {
    final id = text(file, 'id', text(file, 'fileId'));
    if (!busyFileIds.add(id)) return;
    setState(() {});
    try {
      await action({
        ...file,
        'courseId': widget.course['id'],
        'courseName': widget.course['name'],
      });
    } finally {
      busyFileIds.remove(id);
      if (mounted) setState(() {});
    }
  }

  bool get _isSelected => isCourseSelected(widget.course);

  bool get _isLearningCreated =>
      widget.course['learningZjuCreated'] == true ||
      (widget.course['learningZjuCreated'] != false &&
          text(widget.course, 'id').isNotEmpty &&
          !text(widget.course, 'id').startsWith('(') &&
          int.tryParse(text(widget.course, 'id')) != null);

  @override
  void initState() {
    super.initState();
    final courseId = text(widget.course, 'id');
    materials = (!_isLearningCreated || courseId.isEmpty)
        ? Future.value(<Json>[])
        : widget.services.campus.materials(courseId);
    assignments = (!_isLearningCreated || courseId.isEmpty)
        ? Future.value(<Json>[])
        : widget.services.campus.assignments(courseId: courseId);
  }

  Future<void> _refreshMaterials() async {
    final id = text(widget.course, 'id');
    if (!_isLearningCreated || id.isEmpty) return;
    setState(() {
      materials = widget.services.campus.materials(id, refresh: true);
    });
  }

  Future<void> _refreshAssignments() async {
    final id = text(widget.course, 'id');
    if (!_isLearningCreated || id.isEmpty) return;
    setState(() {
      assignments = widget.services.campus.assignments(
        courseId: id,
        refresh: true,
      );
    });
  }

  void _openAssignmentDetail(Json a) {
    final enriched = {
      ...a,
      if (text(a, 'courseName').isEmpty)
        'courseName': text(widget.course, 'name'),
      if (text(a, 'courseId').isEmpty) 'courseId': text(widget.course, 'id'),
    };
    if (widget.onAssignmentDetail != null) {
      widget.onAssignmentDetail!(enriched);
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: paperCard,
        builder: (ctx) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .8,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                text(enriched, 'title'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${text(enriched, 'courseName')} · ${formatDateTime(text(enriched, 'deadline'))}',
                style: const TextStyle(color: ink),
              ),
              const Divider(height: 28),
              MarkdownBody(
                data:
                    html.parse(text(enriched, 'description')).body?.text ??
                    '暂无作业说明',
                selectable: true,
              ),
              const SizedBox(height: 12),
              for (final f in rows(enriched['attachments'] ?? []))
                ListTile(
                  title: Text(text(f, 'name')),
                  leading: const Icon(Icons.attach_file),
                  trailing: const Icon(Icons.download),
                  onTap: () => widget.onDownload({
                    ...f,
                    'courseId': enriched['courseId'],
                    'courseName': enriched['courseName'],
                  }),
                ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildCourseMetaRow() {
    final teacher = text(widget.course, 'teacher');
    final location = text(widget.course, 'location');
    final time = text(widget.course, 'scheduleTime');
    final creditVal = double.tryParse('${widget.course['credit']}') ?? 0.0;
    final score = text(
      widget.course,
      'score',
      text(widget.course, 'original'),
    ).trim();
    final gpa = text(
      widget.course,
      'gpa',
      text(widget.course, 'fivePoint'),
    ).trim();
    final gradeBadge = formatGradeBadge(score, gpa);

    if (teacher.isEmpty &&
        location.isEmpty &&
        time.isEmpty &&
        creditVal <= 0 &&
        gradeBadge.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (!_isSelected)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: ink.withValues(alpha: .65),
                ),
                const SizedBox(width: 4),
                Text(
                  '未选中',
                  style: TextStyle(
                    fontSize: 12,
                    color: ink.withValues(alpha: .65),
                  ),
                ),
              ],
            )
          else if (!_isLearningCreated)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 13,
                  color: ink.withValues(alpha: .65),
                ),
                const SizedBox(width: 4),
                Text(
                  '未建课',
                  style: TextStyle(
                    fontSize: 12,
                    color: ink.withValues(alpha: .65),
                  ),
                ),
              ],
            ),
          if (time.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time, size: 13, color: ink),
                const SizedBox(width: 4),
                Text(time, style: const TextStyle(fontSize: 12, color: ink)),
              ],
            ),
          if (location.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.room_outlined, size: 13, color: ink),
                const SizedBox(width: 4),
                Text(
                  location,
                  style: const TextStyle(fontSize: 12, color: ink),
                ),
              ],
            ),
          if (teacher.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline, size: 13, color: ink),
                const SizedBox(width: 4),
                Text(teacher, style: const TextStyle(fontSize: 12, color: ink)),
              ],
            ),
          if (creditVal > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars_outlined, size: 13, color: ink),
                const SizedBox(width: 4),
                Text(
                  '${creditVal.toStringAsFixed(creditVal.truncateToDouble() == creditVal ? 0 : 1)} 学分',
                  style: const TextStyle(fontSize: 12, color: ink),
                ),
              ],
            ),
          if (gradeBadge.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_outlined, size: 13, color: seal),
                const SizedBox(width: 4),
                Text(
                  gradeBadge,
                  style: const TextStyle(
                    fontSize: 12,
                    color: seal,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .9,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
          child: Row(
            children: [
              const Icon(Icons.school_outlined, color: gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text(widget.course, 'name'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        _buildCourseMetaRow(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('课件资料'),
                selected: currentTab == 'materials',
                selectedColor: blue.withValues(alpha: .16),
                onSelected: (_) {
                  if (currentTab != 'materials') {
                    setState(() => currentTab = 'materials');
                    widget.onTabChanged?.call('materials');
                  }
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('课程作业'),
                selected: currentTab == 'assignments',
                selectedColor: blue.withValues(alpha: .16),
                onSelected: (_) {
                  if (currentTab != 'assignments') {
                    setState(() => currentTab = 'assignments');
                    widget.onTabChanged?.call('assignments');
                  }
                },
              ),
              if (!_isSelected) ...[
                const Spacer(),
                Flexible(
                  child: Text(
                    '教务网未选中此课程',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: ink.withValues(alpha: .5),
                    ),
                  ),
                ),
              ] else if (!_isLearningCreated) ...[
                const Spacer(),
                Flexible(
                  child: Text(
                    '学在浙大无此课程',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: ink.withValues(alpha: .5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: currentTab == 'materials'
              ? _buildMaterials()
              : _buildAssignments(),
        ),
      ],
    ),
  );

  Widget _buildMaterials() => FutureBuilder<List<Json>>(
    future: materials,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: blue));
      }
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: seal),
              const SizedBox(height: 10),
              Text(
                snapshot.error is AppError
                    ? (snapshot.error as AppError).message
                    : '课件加载失败，请稍后重试',
                style: const TextStyle(color: ink),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _refreshMaterials,
                child: const Text('重新加载'),
              ),
            ],
          ),
        );
      }
      final items = snapshot.data ?? [];
      if (items.isEmpty) {
        return const PageEmpty(icon: 'folder', title: '该课程暂无资料');
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final m in items)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: paper,
                border: Border.all(color: ink.withValues(alpha: .15)),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text(m, 'title'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (rows(m['files']).isEmpty)
                    const Text(
                      '无附件',
                      style: TextStyle(fontSize: 12, color: ink),
                    )
                  else
                    for (final f in rows(m['files']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          text(f, 'name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            Builder(
                              builder: (context) {
                                final fileId = text(f, 'id', text(f, 'fileId'));
                                final busy = busyFileIds.contains(fileId);
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OutlinedButton(
                                      onPressed: !busy
                                          ? () => runFileAction(
                                              f,
                                              widget.onPreview,
                                            )
                                          : null,
                                      child: const Text('预览'),
                                    ),
                                    FilledButton(
                                      onPressed: !busy
                                          ? () => runFileAction(
                                              f,
                                              widget.onDownload,
                                            )
                                          : null,
                                      child: busy
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: paperCard,
                                              ),
                                            )
                                          : const Text('下载'),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _buildAssignments() => FutureBuilder<List<Json>>(
    future: assignments,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator(color: blue));
      }
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: seal),
              const SizedBox(height: 10),
              Text(
                snapshot.error is AppError
                    ? (snapshot.error as AppError).message
                    : '作业加载失败，请稍后重试',
                style: const TextStyle(color: ink),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _refreshAssignments,
                child: const Text('重新加载'),
              ),
            ],
          ),
        );
      }
      final items = snapshot.data ?? [];
      if (items.isEmpty) {
        return const PageEmpty(
          icon: 'checklist-paper',
          title: '该课程暂无作业',
          description: '当前课程下未发布任何作业任务。',
        );
      }
      final sorted = List<Json>.from(items)..sort(compareAssignments);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final a in sorted)
            AssignmentCard(
              assignment: {
                ...a,
                if (text(a, 'courseName').isEmpty)
                  'courseName': text(widget.course, 'name'),
              },
              now: DateTime.now(),
              urgentHours: 48,
              backgroundColor: paper,
              onTap: () => _openAssignmentDetail(a),
            ),
        ],
      );
    },
  );
}
