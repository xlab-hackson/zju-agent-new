import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:html/parser.dart' as html;
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/campus.dart';
import '../application/services.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import 'export.dart';
import 'avatar.dart';
import 'theme.dart';

const _dayNames = ['一', '二', '三', '四', '五', '六', '日'];

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) {
    throw const AppError('INVALID_INPUT', '链接地址无效。');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const AppError('SERVICE_UNAVAILABLE', '无法打开外部链接。');
  }
}

class FeaturePage extends StatefulWidget {
  const FeaturePage({super.key, required this.services, required this.page});
  final AppServices services;
  final String page;

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  late Future<Json> data;
  String semester = academicSemester(beijing(DateTime.now()));
  String assignmentTab = 'urgent';
  String noticeSource = 'all';
  String upcomingTab = 'schedule';
  int urgentHours = 24;
  DateTime now = DateTime.now();
  Timer? ticker;
  bool _refreshing = false;
  final exportKey = GlobalKey();

  AppServices get s => widget.services;

  bool get hasRightPanel => widget.page == '/courses';

  @override
  void initState() {
    super.initState();
    data = load(refresh: s.claimInitialRefresh(widget.page));
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final next = load(refresh: true);
    if (mounted) {
      setState(() {
        data = next;
      });
    }
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the page error; refresh controls should settle.
    } finally {
      _refreshing = false;
    }
  }

  Future<Json> load({bool refresh = false}) async {
    switch (widget.page) {
      case '/courses':
        final semesters = await s.campus.semesters(refresh: refresh);
        final all = semester == 'all';
        return {
          'semesters': semesters,
          'courses': await s.campus.courses(
            semesterId: all ? null : semester,
            refresh: refresh,
          ),
          'timetable': all
              ? <Json>[]
              : (await s.campus.timetable(
                  semester,
                  refresh: refresh,
                )).map((e) => e.toJson()).toList(),
        };
      case '/assignments':
        return {
          'items': await s.campus.assignments(
            semesterId: semester,
            refresh: refresh,
          ),
        };
      case '/exams':
        return {
          'items': await s.campus.exams(semester, refresh: refresh),
          'semesters': await s.campus.semesters(refresh: refresh),
        };
      case '/school-info':
        return s.campus.notices();
      case '/downloads':
        var downloadCourses = <Json>[];
        try {
          final cached = await s.db.get('cache', 'courses');
          if (cached != null) downloadCourses = rows(cached['items']);
        } catch (_) {
          // A malformed cache must not hide the download records.
        }
        // Keep this page local-only. A download/delete must not wait for a
        // course refresh before the other download cards become interactive.
        return {
          'items': await s.db.list('downloads'),
          'courses': downloadCourses,
          'downloadDir': s.files.root.path,
        };
      case '/classroom':
        return {};
      default:
        final campus = await s.secrets.read('campus');
        final hasCampusCredential = campus != null;
        final providers = await s.secrets.read('providers');
        final result = <String, dynamic>{
          'settings': await s.db.get('settings', 'app') ?? {},
          'hasCampusCredential': hasCampusCredential,
          'campusStatus': hasCampusCredential
              ? s.campus.session.authStatus
              : 'missing',
          'hasModel': rows(providers?['items'] ?? []).isNotEmpty,
        };
        for (final entry in <String, Future<Object?> Function()>{
          'schedule': () => s.campus.upcoming(),
          'timetable': () async => (await s.campus.timetable(
            semester,
          )).map((entry) => entry.toJson()).toList(),
          'assignments': () => s.campus.assignments(semesterId: semester),
          'courses': () => s.campus.courses(semesterId: semester),
          'exams': () => s.campus.exams(semester),
        }.entries) {
          try {
            result[entry.key] = await entry.value();
          } on AppError catch (e) {
            result['${entry.key}Error'] = e.message;
          }
        }
        result['campusStatus'] = hasCampusCredential
            ? s.campus.session.authStatus
            : 'missing';
        return result;
    }
  }

  Future<void> act(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is AppError ? e.message : '操作失败，请重试。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      return CustomPaint(
        painter: PaperLines(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _scrollableContent(wide)),
                if (wide && hasRightPanel) _rightPanel(constraints.maxWidth),
              ],
            ),
            if (!wide && hasRightPanel)
              Positioned(
                right: 16,
                bottom: 80,
                child: FloatingActionButton.small(
                  heroTag: 'right-panel-${widget.page}',
                  tooltip: '打开辅助面板',
                  onPressed: openRightPanel,
                  backgroundColor: blue,
                  foregroundColor: paperCard,
                  child: const Icon(Icons.tune),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _scrollableContent(bool wide) {
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        wide ? 38 : 16,
        wide ? 32 : 24,
        wide ? 38 : 16,
        100,
      ),
      child: FutureBuilder<Json>(
        future: data,
        builder: (context, snapshot) => _mainContent(snapshot, wide: wide),
      ),
    );
    if (wide || widget.page == '/school-info') return scroll;
    return RefreshIndicator(
      color: blue,
      backgroundColor: paperCard,
      onRefresh: refresh,
      child: scroll,
    );
  }

  Widget _rightPanel(double width) => SizedBox(
    width: width >= 1200 ? 288 : 260,
    child: Container(
      decoration: BoxDecoration(
        color: paperCard.withValues(alpha: .62),
        border: Border(left: BorderSide(color: ink.withValues(alpha: .15))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
      child: RefreshIndicator(
        color: blue,
        backgroundColor: paperCard,
        onRefresh: refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: _rightPanelContent(),
        ),
      ),
    ),
  );

  Widget _rightPanelContent({VoidCallback? onPanelChanged}) =>
      FutureBuilder<Json>(
        future: data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final d = snapshot.data!;
          switch (widget.page) {
            case '/courses':
              return CourseRightPanel(
                data: d,
                selected: semester,
                onChanged: (value) {
                  semester = value;
                  refresh();
                  onPanelChanged?.call();
                },
                onSelect: courseDetail,
              );
            case '/assignments':
              return AssignmentRightPanel(
                data: d,
                hours: urgentHours,
                onHoursChanged: (value) {
                  setState(() => urgentHours = value);
                  onPanelChanged?.call();
                },
              );
            default:
              return const SizedBox.shrink();
          }
        },
      );

  Future<void> openRightPanel() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: paperCard,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .82,
        child: RefreshIndicator(
          color: blue,
          backgroundColor: paperCard,
          onRefresh: refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: _rightPanelContent(
              onPanelChanged: () => setSheetState(() {}),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _mainContent(AsyncSnapshot<Json> snapshot, {required bool wide}) {
    if (widget.page == '/') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _dashboard(snapshot),
      );
    }
    final title =
        <String, String>{
          '/courses': '课程表',
          '/assignments': '待办作业',
          '/exams': '考试安排',
          '/school-info': '学校信息',
          '/downloads': '下载中心',
          '/classroom': '智云课堂',
        }[widget.page] ??
        '工作台';
    final subtitle = widget.page == '/school-info'
        ? '素质拓展平台与教务系统的最新通知公告，点击条目在浏览器打开原文'
        : null;
    final choices = widget.page == '/courses' || widget.page == '/exams'
        ? semesterChoices(rows(snapshot.data?['semesters'] ?? []))
        : const <SemesterChoice>[];
    final body = <Widget>[
      PageHead(
        title: title,
        subtitle: subtitle,
        trailing: IconButton(
          onPressed: refresh,
          tooltip: widget.page == '/school-info' ? '刷新通知' : '刷新',
          icon: const Icon(Icons.refresh, size: 18),
        ),
      ),
      if (choices.isNotEmpty && (!wide || widget.page == '/exams'))
        _semesterPicker(choices),
      if (widget.page == '/assignments' && snapshot.hasData)
        Paper(
          child: AssignmentRightPanel(
            data: snapshot.data!,
            hours: urgentHours,
            onHoursChanged: (value) => setState(() => urgentHours = value),
          ),
        ),
      _asyncBody(snapshot, wide: wide),
      if (s.campus.stale.isNotEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('网络暂不可用，部分内容来自本地缓存。', style: TextStyle(color: gold)),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: body);
  }

  Widget _semesterPicker(List<SemesterChoice> choices) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      isExpanded: true,
      value: choices.any((choice) => choice.id == semester)
          ? semester
          : (choices.isEmpty ? null : choices.first.id),
      decoration: const InputDecoration(labelText: '学期'),
      items: [
        for (final choice in choices)
          DropdownMenuItem(
            value: choice.id,
            child: Text(
              choice.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        semester = value;
        refresh();
      },
    ),
  );

  Widget _asyncBody(AsyncSnapshot<Json> snapshot, {required bool wide}) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Paper(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(54),
            child: CircularProgressIndicator(color: blue),
          ),
        ),
      );
    }
    if (snapshot.hasError) {
      return Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off, color: seal),
            const SizedBox(height: 12),
            Text(
              snapshot.error is AppError
                  ? (snapshot.error as AppError).message
                  : '加载失败，请重试。',
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: refresh, child: const Text('重新加载')),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: content(snapshot.data ?? {}, wide: wide),
    );
  }

  List<Widget> content(Json d, {required bool wide}) {
    switch (widget.page) {
      case '/courses':
        return _courses(d, wide: wide);
      case '/assignments':
        return _assignments(d);
      case '/exams':
        return _exams(d);
      case '/school-info':
        return _schoolInfo(d);
      case '/downloads':
        return _downloads(d);
      case '/classroom':
        return [
          Paper(
            child: PageEmpty(
              icon: 'video-lesson-play',
              title: '智云课堂尚未开放',
              description: '课堂回放、课件下载与语音检索将在服务接入后开放。',
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  List<Widget> _courses(Json d, {required bool wide}) {
    final entries = rows(d['timetable']).map(TimetableEntry.fromJson).toList();
    final courses = rows(d['courses']);
    final result = <Widget>[];
    if (semester == 'all') {
      result.add(
        Paper(
          child: PageEmpty(
            icon: 'calendar-days',
            title: '已切换为「全部学期」总览',
            description: '右侧总览已展示全部历史课程。课表按单学期排列，请选择具体学期查看课表。',
          ),
        ),
      );
    } else if (entries.isEmpty) {
      result.add(
        Paper(
          child: PageEmpty(icon: 'calendar-grid', title: '该学期暂无课表数据'),
        ),
      );
    } else {
      result.add(
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          runSpacing: 2,
          children: [
            TextButton.icon(
              onPressed: () => act(() => exportPng(exportKey, semester)),
              icon: const Icon(Icons.image_outlined, size: 16),
              label: const Text('导出图片'),
            ),
            TextButton.icon(
              onPressed: () => act(() => exportXlsx(entries, semester)),
              icon: const Icon(Icons.table_chart_outlined, size: 16),
              label: const Text('导出 Excel'),
            ),
            IconButton(
              onPressed: refresh,
              tooltip: '刷新课程表',
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
      );
      result.add(
        RepaintBoundary(
          key: exportKey,
          child: TimetableView(entries: entries, semester: semester),
        ),
      );
    }
    if (!wide) {
      result.add(const SizedBox(height: 24));
      result.add(const ChapterHead(title: '课程目录', icon: 'book-open'));
      if (courses.isEmpty) {
        result.add(const Text('该学期暂无学在浙大课程。', style: TextStyle(color: ink)));
      } else {
        for (final course in courses) result.add(_courseButton(course));
      }
    }
    return result;
  }

  Widget _courseButton(Json course) => Paper(
    padding: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(Icons.menu_book, color: blue),
      title: Text(text(course, 'name')),
      subtitle: Text(text(course, 'teachingClassName')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => courseDetail(course),
    ),
  );

  List<Widget> _assignments(Json d) {
    final all = rows(d['items']);
    final nowMs = now.millisecondsSinceEpoch;
    final threshold = nowMs + urgentHours * 3600 * 1000;
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
              deadlineMs(a) != null &&
              deadlineMs(a)! > threshold,
        )
        .toList();
    final submitted = all.where(isSubmitted).toList();
    final selected = switch (assignmentTab) {
      'relaxed' => relaxed,
      'overdue' => overdue,
      'submitted' => submitted,
      _ => urgent,
    };
    final tabs = [
      ('urgent', '将截止', urgent.length, seal),
      ('relaxed', '还不急', relaxed.length, gold),
      ('overdue', '已截止', overdue.length, ink),
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
                  onSelected: (_) => setState(() => assignmentTab = tab.$1),
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
              'overdue' => '暂无逾期作业',
              _ => '暂无已提交作业',
            },
            description: '当前分类下没有相关作业记录。',
          ),
        )
      else
        for (final assignment in selected) _assignmentCard(assignment),
    ];
  }

  Widget _assignmentCard(Json a) {
    final deadline = deadlineMs(a);
    final overdue = deadline != null && deadline <= now.millisecondsSinceEpoch;
    final urgent =
        deadline != null &&
        !overdue &&
        deadline - now.millisecondsSinceEpoch <= urgentHours * 3600 * 1000;
    final status = isSubmitted(a)
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
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: () => assignmentDetail(a),
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
                        text(a, 'title'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text(a, 'courseName'),
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
                  '截止：${formatDateTime(text(a, 'deadline'))}',
                  style: const TextStyle(fontSize: 12, color: ink),
                ),
                if (rows(a['attachments'] ?? []).isNotEmpty) ...[
                  const SizedBox(width: 12),
                  InkTag(
                    label: '附件 ${rows(a['attachments'] ?? []).length}',
                    color: ink,
                  ),
                ],
              ],
            ),
            if (text(a, 'description').isNotEmpty) ...[
              const Divider(height: 22),
              Text(
                html.parse(text(a, 'description')).body?.text ?? '',
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

  List<Widget> _exams(Json d) {
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

  List<Widget> _schoolInfo(Json d) {
    final all = rows(d['items']);
    final failures = (d['failures'] as List? ?? []).map((e) => '$e').toList();
    final items = noticeSource == 'all'
        ? all
        : all.where((n) => n['source'] == noticeSource).toList();
    return [
      Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final choice in [
            ('all', '全部'),
            ('sztz', '素质拓展'),
            ('zdbk', '教务系统'),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(choice.$2),
                selected: noticeSource == choice.$1,
                onSelected: (_) => setState(() => noticeSource = choice.$1),
              ),
            ),
        ],
      ),
      if (failures.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: gold.withValues(alpha: .1),
            border: Border.all(color: gold.withValues(alpha: .45)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_none, color: gold, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failures.join('；'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      if (items.isEmpty)
        Paper(
          child: const PageEmpty(icon: 'announcement-horn', title: '暂无通知'),
        )
      else
        for (final notice in items) _noticeCard(notice),
    ];
  }

  Widget _noticeCard(Json notice) {
    final summary = stripHtmlText(text(notice, 'summary'));
    return Paper(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: InkWell(
        onTap: () => act(() => openExternal(text(notice, 'url'))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (notice['important'] == true)
                        const InkTag(label: '置顶', color: seal, filled: true),
                      InkTag(
                        label: notice['source'] == 'sztz' ? '素质拓展' : '教务系统',
                        color: notice['source'] == 'sztz'
                            ? const Color(0xff2e7d32)
                            : seal,
                      ),
                      Text(
                        text(notice, 'title'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (summary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  const SizedBox(height: 7),
                  Text(
                    '${text(notice, 'date')}  ${text(notice, 'publisher')}',
                    style: const TextStyle(fontSize: 11, color: ink),
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new, size: 16, color: gold),
          ],
        ),
      ),
    );
  }

  List<Widget> _downloads(Json d) {
    final files = rows(d['items']);
    final courseNames = <String, String>{
      for (final course in rows(d['courses'] ?? []))
        text(course, 'id'): text(course, 'name'),
    };
    final grouped = <String, List<Json>>{};
    final groupNames = <String, String>{};
    for (final file in files) {
      final courseId = text(file, 'courseId');
      final storedName = text(file, 'courseName').trim();
      final storedFolder = text(file, 'courseFolder').trim();
      final lookedUpName = courseNames[courseId]?.trim() ?? '';
      final courseName = storedName.isNotEmpty
          ? storedName
          : lookedUpName.isNotEmpty
          ? lookedUpName
          : storedFolder.isNotEmpty
          ? storedFolder
          : courseId.isEmpty
          ? '未分类'
          : '课程 $courseId';
      final groupId = courseId.isNotEmpty
          ? courseId
          : storedFolder.isNotEmpty
          ? 'folder:$storedFolder'
          : 'uncategorized';
      groupNames[groupId] = courseName;
      grouped.putIfAbsent(groupId, () => []).add({
        ...file,
        'courseName': courseName,
      });
    }
    final groups = grouped.entries.toList()
      ..sort(
        (a, b) => (groupNames[a.key] ?? '').compareTo(groupNames[b.key] ?? ''),
      );
    return [
      if (files.isEmpty)
        Paper(
          child: PageEmpty(
            icon: 'folder',
            title: '还没有下载过文件',
            description: '前往「课程」页下载课件后会出现在这里。',
          ),
        )
      else
        for (final group in groups) ...[
          ChapterHead(
            title: groupNames[group.key] ?? '未分类',
            icon: 'book-open',
            trailing: Text(
              '${group.value.length} 个文件',
              style: const TextStyle(fontSize: 12, color: ink),
            ),
          ),
          for (final file in group.value)
            DownloadCard(services: s, record: file, onChanged: refresh),
        ],
    ];
  }

  List<Widget> _dashboard(AsyncSnapshot<Json> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return [
        const Center(
          child: Padding(
            padding: EdgeInsets.all(70),
            child: CircularProgressIndicator(color: blue),
          ),
        ),
      ];
    }
    if (snapshot.hasError) return [Paper(child: Text('${snapshot.error}'))];
    final d = snapshot.data ?? {};
    final settings = object(d['settings'] ?? {});
    final schedule = object(d['schedule'] ?? {});
    final events = rows(schedule['events'] ?? []);
    final allAssignments = rows(d['assignments'] ?? []);
    final pending = allAssignments
        .where((a) => a['submitted'] != true)
        .toList();
    final assignments48h = pending.where((a) {
      final due = deadlineMs(a);
      return due != null &&
          due <= now.millisecondsSinceEpoch + 48 * 3600 * 1000 &&
          due >= now.millisecondsSinceEpoch;
    }).toList();
    final courses = rows(d['courses'] ?? []);
    final timetable = rows(
      d['timetable'] ?? [],
    ).map(TimetableEntry.fromJson).toList();
    final courseCount = timetableCourseCount(timetable);
    final exams = rows(d['exams'] ?? []);
    final dateInfo = object(schedule['dateInfo'] ?? {});
    final name = text(settings, 'nickname').trim().isEmpty
        ? '浙大学子'
        : text(settings, 'nickname');
    final avatarDataUrl = text(settings, 'avatarDataUrl');
    final campusStatus = text(d, 'campusStatus', 'missing');
    return [
      _dashboardHeader(name, dateInfo, campusStatus, avatarDataUrl),
      ChapterHead(
        juan: '卷一',
        title: '接下来',
        icon: 'cartoon-hourglass',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChoiceChip(
              label: const Text('日程'),
              selected: upcomingTab == 'schedule',
              onSelected: (_) => setState(() => upcomingTab = 'schedule'),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: Text('作业 ${assignments48h.length}'),
              selected: upcomingTab == 'assignments',
              onSelected: (_) => setState(() => upcomingTab = 'assignments'),
            ),
          ],
        ),
      ),
      if (upcomingTab == 'schedule')
        _dashboardSchedule(events, dateInfo)
      else
        _dashboardAssignments(assignments48h),
      ChapterHead(juan: '卷二', title: '学业快览', icon: 'area-chart'),
      _kpiRow(
        courseCount > 0 ? courseCount : courses.length,
        pending.length,
        exams.length,
      ),
      ChapterHead(juan: '卷三', title: '校园百宝箱', icon: 'scroll'),
      _toolGrid(),
      ChapterHead(juan: '卷四', title: '系统与连接', icon: 'key'),
      _connectionGrid(d),
    ];
  }

  Widget _dashboardHeader(
    String name,
    Json info,
    String campusStatus,
    String avatarDataUrl,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${DateTime.now().year} 年   ${_monthName(DateTime.now().month)} ${DateTime.now().day}   ${_weekday(DateTime.now().weekday)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: gold,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(height: 1, color: gold.withValues(alpha: .45)),
            ),
            IconButton(
              onPressed: refresh,
              tooltip: '刷新工作台',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(dataUrl: avatarDataUrl, radius: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '你好，$name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (info.isNotEmpty)
                        InkTag(
                          label:
                              '${text(info, 'semesterId')} · ${text(info, 'weekString', '本学期')}',
                          color: blue,
                        ),
                      if (info['isHoliday'] == true)
                        InkTag(
                          label: '休：${text(info, 'holidayName', '放假')}',
                          color: gold,
                          dot: true,
                        ),
                      InkTag(
                        label: switch (campusStatus) {
                          'connected' => '教务已同步',
                          'invalid' => '登录已失效',
                          'unknown' => '待验证登录',
                          _ => '待绑定账号',
                        },
                        color: campusStatus == 'connected'
                            ? const Color(0xff2e7d32)
                            : gold,
                        dot: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Transform.rotate(
              angle: .08,
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: seal, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '浙大\n助手',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: seal, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _dashboardSchedule(List<Json> events, Json info) {
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
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final event in events)
              SizedBox(width: width, child: _eventCard(event)),
          ],
        );
      },
    );
  }

  Widget _eventCard(Json event) => Paper(child: _eventCardBody(event));

  Widget _eventCardBody(Json event) {
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

  Widget _dashboardAssignments(List<Json> assignments) {
    if (assignments.isEmpty)
      return Paper(
        child: const PageEmpty(
          icon: 'checklist-paper',
          title: '近四十八小时暂无紧急待交作业',
          description: '所有待办作业均在安全期内或已全部提交完毕。',
        ),
      );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final a in assignments)
              SizedBox(width: width, child: _assignmentCard(a)),
          ],
        );
      },
    );
  }

  Widget _kpiRow(int courses, int assignments, int exams) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 560
          ? 2
          : 1;
      const gap = 6.0;
      const cardHeight = 190.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: width,
            height: cardHeight,
            child: Kpi(
              label: '本学期课程',
              value: '$courses',
              unit: '门',
              foot: '秋冬课表',
              icon: 'book-open',
              onTap: () => context.go('/courses'),
            ),
          ),
          SizedBox(
            width: width,
            height: cardHeight,
            child: Kpi(
              label: '待办作业',
              value: '$assignments',
              unit: '项待交',
              foot: '截止一览',
              icon: 'checklist-paper',
              onTap: () => context.go('/assignments'),
            ),
          ),
          SizedBox(
            width: width,
            height: cardHeight,
            child: Kpi(
              label: '考试安排',
              value: '$exams',
              unit: '场待考',
              foot: '考场考签',
              icon: 'exam-paper',
              onTap: () => context.go('/exams'),
            ),
          ),
          SizedBox(
            width: width,
            height: cardHeight,
            child: Kpi(
              label: '下载中心',
              value: '本地文库',
              unit: '',
              foot: '课件与资料',
              icon: 'folder',
              small: true,
              onTap: () => context.go('/downloads'),
            ),
          ),
        ],
      );
    },
  );

  Widget _toolGrid() {
    const tools = [
      ('智云课堂', 'video-lesson-play', 'https://classroom.zju.edu.cn'),
      ('学在浙大', 'graduation-cap', 'https://courses.zju.edu.cn'),
      ('本科生教务系统', 'university', 'http://jwbinfosys.zju.edu.cn'),
      ('CC98 论坛', 'comment-thread', 'https://www.cc98.org'),
      ('校网充值与查询', 'payment-card', 'https://myvpn.zju.edu.cn'),
      ('图书馆座位预约', 'library-public', 'http://libsys.zju.edu.cn'),
      ('校务综合服务大厅', 'school-building', 'https://service.zju.edu.cn'),
      ('ETA 成绩分析', 'area-chart', null),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 42) / 4
            : constraints.maxWidth >= 560
            ? (constraints.maxWidth - 14) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final tool in tools)
              SizedBox(
                width: width,
                height: 200,
                child: ToolCard(
                  title: tool.$1,
                  icon: tool.$2,
                  url: tool.$3,
                  onOpen: tool.$3 == null
                      ? null
                      : () => act(() => openExternal(tool.$3!)),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _connectionGrid(Json d) => LayoutBuilder(
    builder: (context, constraints) {
      final status = text(d, 'campusStatus', 'missing');
      final connected = status == 'connected';
      final configured = d['hasCampusCredential'] == true;
      final label = switch (status) {
        'connected' => '已连接',
        'invalid' => '登录已失效',
        'unknown' => '待验证',
        _ => '未配置',
      };
      final width = constraints.maxWidth >= 700
          ? (constraints.maxWidth - 14) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          SizedBox(
            width: width,
            child: ConnectionCard(
              title: '统一身份认证（ZJU）',
              ok: connected,
              configured: configured,
              statusLabel: label,
              detail: switch (status) {
                'connected' => '已连接学在浙大、教学教务与考场系统',
                'invalid' => '最近一次校园请求未通过认证，请重新登录或检查账号状态',
                'unknown' => '已保存账号，但尚未验证当前校园登录状态',
                _ => '绑定后即可一键拉取课表、同步作业与考签',
              },
              action: () => context.go('/setup'),
            ),
          ),
          SizedBox(
            width: width,
            child: ConnectionCard(
              title: '大模型 API 接口',
              ok: d['hasModel'] == true,
              detail: d['hasModel'] == true ? '模型来源已配置，可使用问学助手' : '尚未配置模型来源',
              action: () => context.go('/settings'),
            ),
          ),
        ],
      );
    },
  );

  Future<void> assignmentDetail(Json a) => showModalBottomSheet<void>(
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
            text(a, 'title'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            '${text(a, 'courseName')} · ${formatDateTime(text(a, 'deadline'))}',
            style: const TextStyle(color: ink),
          ),
          const Divider(height: 28),
          MarkdownBody(
            data: html.parse(text(a, 'description')).body?.text ?? '暂无作业说明',
            selectable: true,
          ),
          const SizedBox(height: 12),
          for (final f in rows(a['attachments'] ?? []))
            ListTile(
              title: Text(text(f, 'name')),
              leading: const Icon(Icons.attach_file),
              trailing: const Icon(Icons.download),
              onTap: () => downloadFile({
                ...f,
                'courseId': a['courseId'],
                'courseName': a['courseName'],
              }),
            ),
        ],
      ),
    ),
  );

  Future<void> courseDetail(Json c) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: paperCard,
    builder: (ctx) => CourseDetailSheet(
      services: s,
      course: c,
      onDownload: downloadFile,
      onPreview: previewFile,
    ),
  );

  Future<void> downloadFile(Json f) async {
    await act(() async {
      await s.files.download({
        'courseId': text(f, 'courseId'),
        'fileId': text(f, 'id', text(f, 'fileId')),
        'fileName': text(f, 'name', text(f, 'fileName')),
        'courseName': text(f, 'courseName'),
        'officePdf': false,
      });
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已保存，可在下载页打开。')));
    });
  }

  Future<void> previewFile(Json f) async {
    await act(() async {
      final name = text(f, 'name', text(f, 'fileName'));
      final record = await s.files.download({
        'courseId': text(f, 'courseId'),
        'fileId': text(f, 'id', text(f, 'fileId')),
        'fileName': name,
        'courseName': text(f, 'courseName'),
        'officePdf': isOfficeDocument(name),
      });
      final file = await s.files.file(record);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: paperCard,
        builder: (ctx) => PreviewSheet(
          file: file,
          name: text(record, 'fileName', name),
          kind: fileKind(text(record, 'fileName', name)),
          onOpen: () => act(() => openLocalFile(file)),
        ),
      );
    });
  }

  Future<void> openLocalFile(File file) async {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw AppError('FILE_OPEN_FAILED', result.message);
    }
  }
}

class CourseRightPanel extends StatelessWidget {
  const CourseRightPanel({
    super.key,
    required this.data,
    required this.selected,
    required this.onChanged,
    required this.onSelect,
  });
  final Json data;
  final String selected;
  final ValueChanged<String> onChanged;
  final ValueChanged<Json> onSelect;

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
    final courses = rows(data['courses']);
    final entries = rows(
      data['timetable'],
    ).map(TimetableEntry.fromJson).toList();
    final groups = <String, List<Json>>{};
    for (final c in courses)
      groups.putIfAbsent(text(c, 'semesterId'), () => []).add(c);
    return SideSection(
      title: '学期总览',
      icon: 'scroll',
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
                  : '本学期 ${entries.isNotEmpty ? entries.map((e) => e.courseName).toSet().length : courses.length} 门',
              style: const TextStyle(fontSize: 11, color: ink),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: choices.any((c) => c.id == selected)
              ? selected
              : (choices.isEmpty ? null : choices.first.id),
          items: [
            for (final c in choices)
              DropdownMenuItem(
                value: c.id,
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: choices.isEmpty
              ? null
              : (v) {
                  if (v != null) onChanged(v);
                },
          decoration: const InputDecoration(isDense: true),
        ),
        const SizedBox(height: 18),
        if (groups.isEmpty)
          const PageEmpty(title: '该学期暂无学在浙大课程')
        else
          for (final group in groups.entries) ...[
            Text(
              '${semesterNames[group.key] ?? group.key}  ${group.value.length} 门',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            for (final course in group.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => onSelect(course),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      side: BorderSide(color: ink.withValues(alpha: .12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text(course, 'name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (text(course, 'teachingClassName').isNotEmpty)
                          Text(
                            text(course, 'teachingClassName'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: ink),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

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
    final all = rows(data['items']);
    final now = DateTime.now().millisecondsSinceEpoch;
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
              deadlineMs(a) != null &&
              deadlineMs(a)! > threshold,
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
                label: '已截止',
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

class CourseDetailSheet extends StatefulWidget {
  const CourseDetailSheet({
    super.key,
    required this.services,
    required this.course,
    required this.onDownload,
    required this.onPreview,
  });
  final AppServices services;
  final Json course;
  final Future<void> Function(Json) onDownload;
  final Future<void> Function(Json) onPreview;
  @override
  State<CourseDetailSheet> createState() => _CourseDetailSheetState();
}

class _CourseDetailSheetState extends State<CourseDetailSheet> {
  late Future<List<Json>> materials;
  final busyFileIds = <String>{};

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

  @override
  void initState() {
    super.initState();
    materials = widget.services.campus.materials(text(widget.course, 'id'));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .9,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              const Icon(Icons.folder_copy_outlined, color: gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '课程资料 · ${text(widget.course, 'name')}',
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
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Json>>(
            future: materials,
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(
                  child: CircularProgressIndicator(color: blue),
                );
              if (snapshot.hasError)
                return Center(child: Text('${snapshot.error}'));
              if (snapshot.data!.isEmpty)
                return const PageEmpty(icon: 'folder', title: '该课程暂无资料');
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final m in snapshot.data!)
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
                                        final fileId = text(
                                          f,
                                          'id',
                                          text(f, 'fileId'),
                                        );
                                        final busy = busyFileIds.contains(
                                          fileId,
                                        );
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
                                                      child:
                                                          CircularProgressIndicator(
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
          ),
        ),
      ],
    ),
  );
}

class DownloadCard extends StatefulWidget {
  const DownloadCard({
    super.key,
    required this.services,
    required this.record,
    required this.onChanged,
  });
  final AppServices services;
  final Json record;
  final VoidCallback onChanged;
  @override
  State<DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<DownloadCard> {
  bool confirming = false;
  bool busy = false;
  AppServices get s => widget.services;
  Json get r => widget.record;
  Future<void> run(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is AppError ? e.message : '操作失败，请重试。')),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = text(r, 'fileName'), kind = fileKind(name);
    final inProgress = text(r, 'status') == 'downloading';
    final canRedownload =
        !inProgress &&
        text(r, 'fileId').isNotEmpty &&
        text(r, 'courseId').isNotEmpty;
    final completed = text(r, 'status') == 'completed';
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      runSpacing: 2,
      children: [
        if (canPreview(kind))
          TextButton(
            onPressed: busy || inProgress ? null : () => preview(),
            child: const Text('预览'),
          ),
        if (inProgress)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text('下载中…', style: TextStyle(color: blue)),
          ),
        if (canRedownload)
          TextButton(
            onPressed: busy ? null : () => run(redownload),
            child: Text(completed ? '重新下载' : '重试下载'),
          ),
        OutlinedButton(
          onPressed: busy || inProgress ? null : () => run(openLocal),
          child: const Text('打开'),
        ),
        if (!confirming)
          TextButton(
            onPressed: busy ? null : () => setState(() => confirming = true),
            child: const Text('删除'),
          )
        else ...[
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await s.files.delete(r, purge: true);
                    widget.onChanged();
                  }),
            style: FilledButton.styleFrom(backgroundColor: seal),
            child: const Text('删文件'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await s.files.delete(r);
                    widget.onChanged();
                  }),
            child: const Text('仅删记录'),
          ),
          IconButton(
            onPressed: () => setState(() => confirming = false),
            icon: const Icon(Icons.close, size: 17),
          ),
        ],
      ],
    );
    return Paper(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatBytes(integer(r['size']))} · ${formatDateTime(text(r, 'createdAt'))}',
                  style: const TextStyle(fontSize: 11, color: ink),
                ),
              ],
            ),
          );
          final header = Row(
            children: [
              Icon(fileIcon(kind), color: fileColor(kind), size: 24),
              const SizedBox(width: 14),
              details,
            ],
          );
          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: header),
              const SizedBox(width: 12),
              Flexible(child: actions),
            ],
          );
        },
      ),
    );
  }

  Future<void> openLocal() async {
    final file = await s.files.file(r);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done)
      throw AppError('FILE_OPEN_FAILED', result.message);
  }

  Future<void> redownload() async {
    await s.files.download({
      'courseId': text(r, 'courseId'),
      'courseName': text(r, 'courseName'),
      'fileId': text(r, 'fileId'),
      'fileName': text(r, 'fileName'),
      'officePdf': r['officePdf'] == true,
    });
    if (text(r, 'status') != 'completed') await s.files.delete(r);
    widget.onChanged();
  }

  Future<void> preview() async {
    final file = await s.files.file(r);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: paperCard,
      builder: (ctx) => PreviewSheet(
        file: file,
        name: text(r, 'fileName'),
        kind: fileKind(text(r, 'fileName')),
        onOpen: openLocal,
      ),
    );
  }
}

class PreviewSheet extends StatelessWidget {
  const PreviewSheet({
    super.key,
    required this.file,
    required this.name,
    required this.kind,
    required this.onOpen,
  });
  final File file;
  final String name, kind;
  final Future<void> Function() onOpen;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .86,
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.article_outlined, color: gold),
          title: const Text(
            '预览',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(name),
          trailing: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(context)),
      ],
    ),
  );
  Widget _body(BuildContext context) {
    if (kind == 'image')
      return Center(
        child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain)),
      );
    if (kind == 'text')
      return FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snapshot) => SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: SelectableText(
            snapshot.data ?? '加载中…',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
      );
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 54, color: gold),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('此类型文件无法在应用内预览，请使用本地软件打开。'),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => onOpen(), child: const Text('用本地软件打开')),
        ],
      ),
    );
  }
}

class TimetableView extends StatelessWidget {
  const TimetableView({
    super.key,
    required this.entries,
    required this.semester,
  });
  final List<TimetableEntry> entries;
  final String semester;
  @override
  Widget build(BuildContext context) {
    final merged = mergeTimetable(entries);
    final courses = merged.map((e) => e.courseName).toSet().toList();
    return Container(
      width: double.infinity,
      color: paperCard,
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(
            '浙江大学课程表（$semester）',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _gridHeader(),
          SizedBox(
            height: 13 * 52,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Column(
                    children: [for (var i = 1; i <= 13; i++) _sectionLabel(i)],
                  ),
                ),
                for (var day = 1; day <= 7; day++)
                  Expanded(child: _dayColumn(day, merged, courses)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridHeader() => Row(
    children: [
      const SizedBox(
        width: 64,
        child: Text(
          '节次\n上课时间',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10, color: ink),
        ),
      ),
      for (final day in _dayNames)
        Expanded(
          child: Center(
            child: Text(
              '周$day',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
    ],
  );
  Widget _sectionLabel(int i) => SizedBox(
    height: 52,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$i',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: blue,
          ),
        ),
        Text(
          '${sessionTimes[i][0]}\n${sessionTimes[i][1]}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 8, color: ink),
        ),
      ],
    ),
  );
  Widget _dayColumn(
    int day,
    List<TimetableEntry> entries,
    List<String> courses,
  ) => Stack(
    children: [
      for (var i = 0; i < 13; i++)
        Positioned(
          top: i * 52,
          left: 0,
          right: 0,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: ink.withValues(alpha: .09)),
            ),
          ),
        ),
      for (final e in entries.where(
        (e) => e.weekday == day && e.startSection <= 13,
      ))
        Positioned(
          top: (e.startSection - 1) * 52 + 2,
          left: 2,
          right: 2,
          height:
              ((e.endSection.clamp(e.startSection, 13) - e.startSection + 1) *
                          52 -
                      4)
                  .toDouble(),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Color(
                courseColors[courses.indexOf(e.courseName) %
                    courseColors.length],
              ),
              border: Border(
                left: BorderSide(color: blue.withValues(alpha: .55), width: 2),
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.courseName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${e.teacher}\n${e.location}\n${e.weeks.isEmpty ? '' : '${compressWeeks(e.weeks)} 周'}',
                    style: const TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class Kpi extends StatefulWidget {
  const Kpi({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.foot,
    required this.icon,
    this.onTap,
    this.small = false,
  });
  final String label, value, unit, foot, icon;
  final VoidCallback? onTap;
  final bool small;

  @override
  State<Kpi> createState() => _KpiState();
}

class _KpiState extends State<Kpi> {
  bool hovered = false, pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = hovered || pressed;
    final color = active ? gold : blue;
    return AnimatedSlide(
      offset: active ? const Offset(0, -.015) : Offset.zero,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: paperCard,
          border: Border.all(
            color: active
                ? gold.withValues(alpha: .58)
                : ink.withValues(alpha: .12),
          ),
          borderRadius: BorderRadius.circular(3),
          boxShadow: active
              ? const [
                  BoxShadow(
                    color: Color(0x1f0e1c38),
                    offset: Offset(1, 4),
                    blurRadius: 8,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            onHover: (value) {
              if (mounted) setState(() => hovered = value);
            },
            onHighlightChanged: (value) {
              if (mounted) setState(() => pressed = value);
            },
            borderRadius: BorderRadius.circular(3),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: active ? -.017 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: SvgPicture.asset(
                          'assets/icons/${widget.icon}.svg',
                          width: 17,
                          height: 17,
                          colorFilter: ColorFilter.mode(
                            color.withValues(alpha: .85),
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            widget.value,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: widget.small ? 20 : 36,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                      if (widget.unit.isNotEmpty)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 5),
                            child: Text(
                              widget.unit,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: ink),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.foot,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: gold,
                            decoration: active
                                ? TextDecoration.underline
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                      AnimatedSlide(
                        offset: active ? const Offset(.15, 0) : Offset.zero,
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          '→',
                          style: TextStyle(fontSize: 16, color: color),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ToolCard extends StatefulWidget {
  const ToolCard({
    super.key,
    required this.title,
    required this.icon,
    required this.url,
    required this.onOpen,
  });
  final String title, icon;
  final String? url;
  final VoidCallback? onOpen;
  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool hovered = false, pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.onOpen != null && (hovered || pressed);
    final iconColor = active ? paperCard : blue;
    final iconAccent = active ? gold : blue;
    final titleColor = active ? gold : ink;
    return AnimatedSlide(
      offset: active ? const Offset(0, -.015) : Offset.zero,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Opacity(
        opacity: widget.url == null ? .62 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: paperCard,
            border: Border.all(
              color: active
                  ? gold.withValues(alpha: .58)
                  : ink.withValues(alpha: .14),
            ),
            borderRadius: BorderRadius.circular(3),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x1f0e1c38),
                      offset: Offset(2, 5),
                      blurRadius: 9,
                    ),
                  ]
                : const [
                    BoxShadow(color: Color(0x110e1c38), offset: Offset(2, 3)),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onOpen,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              onHover: (value) {
                if (mounted) setState(() => hovered = value);
              },
              onHighlightChanged: (value) {
                if (mounted) setState(() => pressed = value);
              },
              borderRadius: BorderRadius.circular(3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedRotation(
                        turns: active ? -3 / 360 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? gold : blue.withValues(alpha: .05),
                            border: Border.all(
                              color: iconAccent.withValues(alpha: .6),
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: SvgPicture.asset(
                            'assets/icons/${widget.icon}.svg',
                            width: 22,
                            height: 22,
                            colorFilter: ColorFilter.mode(
                              iconColor,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                              ),
                            ),
                          ),
                          if (widget.url == null) ...[
                            const SizedBox(width: 8),
                            const InkTag(label: '即将推出', color: ink),
                          ],
                        ],
                      ),
                    ],
                  ),
                  if (widget.url != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: ink.withValues(alpha: .1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.url != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '访问校内服务',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: gold,
                              fontWeight: FontWeight.bold,
                              decoration: active
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                        AnimatedSlide(
                          offset: active ? const Offset(.15, 0) : Offset.zero,
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            '↗',
                            style: const TextStyle(fontSize: 16, color: gold),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.title,
    required this.ok,
    required this.detail,
    required this.action,
    this.configured = false,
    this.statusLabel,
  });
  final String title, detail;
  final bool ok;
  final bool configured;
  final String? statusLabel;
  final VoidCallback action;
  @override
  Widget build(BuildContext context) => Paper(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            InkTag(
              label: statusLabel ?? (ok ? '已连接' : '未配置'),
              color: ok ? const Color(0xff2e7d32) : gold,
              dot: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(detail, style: const TextStyle(fontSize: 12, color: ink)),
        const SizedBox(height: 12),
        TextButton(
          onPressed: action,
          child: Text(ok || configured ? '管理配置  →' : '立即配置  →'),
        ),
      ],
    ),
  );
}

class SideSection extends StatelessWidget {
  const SideSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
  });
  final String title;
  final String? icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (icon != null)
            SvgPicture.asset(
              'assets/icons/$icon.svg',
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(gold, BlendMode.srcIn),
            ),
          if (icon != null) const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: ink.withValues(alpha: .15)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      ...children,
    ],
  );
}

class SideCount extends StatelessWidget {
  const SideCount({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final int value;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Text('$value 项', style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
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

class PageHead extends StatelessWidget {
  const PageHead({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: ink),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = trailing != null && constraints.maxWidth < 520;
          if (!compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: heading),
                if (trailing != null) trailing!,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          );
        },
      ),
    );
  }
}

class ChapterHead extends StatelessWidget {
  const ChapterHead({
    super.key,
    this.juan,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });
  final String title;
  final String? juan, subtitle, icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14, top: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = trailing != null && constraints.maxWidth < 560;
        final row = Row(
          children: [
            if (juan != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: blue,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  juan!,
                  style: const TextStyle(
                    color: paperCard,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (juan != null) const SizedBox(width: 10),
            if (icon != null)
              SvgPicture.asset(
                'assets/icons/$icon.svg',
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(gold, BlendMode.srcIn),
              ),
            if (icon != null) const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            if (subtitle != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: ink),
                  ),
                ),
              ),
            if (subtitle == null && !compact) const Spacer(),
            if (trailing != null && !compact) trailing!,
          ],
        );
        if (!compact) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (juan != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: blue,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      juan!,
                      style: const TextStyle(
                        color: paperCard,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (juan != null) const SizedBox(width: 10),
                if (icon != null)
                  SvgPicture.asset(
                    'assets/icons/$icon.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(gold, BlendMode.srcIn),
                  ),
                if (icon != null) const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: ink),
                ),
              ),
            if (trailing != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: trailing!,
                ),
              ),
          ],
        );
      },
    ),
  );
}

class PageEmpty extends StatelessWidget {
  const PageEmpty({
    super.key,
    this.icon = 'scroll',
    required this.title,
    this.description,
  });
  final String icon, title;
  final String? description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
    child: Center(
      child: Column(
        children: [
          SvgPicture.asset(
            'assets/icons/$icon.svg',
            width: 40,
            height: 40,
            colorFilter: ColorFilter.mode(
              ink.withValues(alpha: .25),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: ink,
            ),
          ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: ink),
              ),
            ),
        ],
      ),
    ),
  );
}

class InkTag extends StatelessWidget {
  const InkTag({
    super.key,
    required this.label,
    required this.color,
    this.dot = false,
    this.filled = false,
  });
  final String label;
  final Color color;
  final bool dot, filled;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: .1),
      border: Border.all(color: color.withValues(alpha: .4)),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        Text(
          label,
          style: TextStyle(
            color: filled ? paperCard : color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

class SemesterChoice {
  const SemesterChoice(this.id, this.name);
  final String id, name;
}

List<SemesterChoice> semesterChoices(List<Json> raw) {
  final map = <String, SemesterChoice>{};
  for (final s in raw) {
    final name = text(s, 'name'), id = semesterToId(name) ?? text(s, 'id');
    if (id.isEmpty) continue;
    map[id] = SemesterChoice(id, semesterDisplay(id, name));
  }
  if (map.isEmpty) {
    final current = academicSemester(beijing(DateTime.now()));
    for (
      var y = beijing(DateTime.now()).year;
      y >= beijing(DateTime.now()).year - 7;
      y--
    ) {
      map['$y-${y + 1}-1'] = SemesterChoice('$y-${y + 1}-1', '$y-${y + 1}秋冬');
      map['$y-${y + 1}-2'] = SemesterChoice('$y-${y + 1}-2', '$y-${y + 1}春夏');
    }
    map.putIfAbsent(
      current,
      () => SemesterChoice(
        current,
        current.endsWith('-1')
            ? '${current.substring(0, 9)}秋冬'
            : '${current.substring(0, 9)}春夏',
      ),
    );
  }
  final result = map.values.toList()..sort((a, b) => b.id.compareTo(a.id));
  result.add(const SemesterChoice('all', '全部学期（所有历史课程）'));
  return result;
}

String semesterDisplay(String id, String name) {
  final normalized = semesterToId(name) ?? id;
  final year = normalized.length >= 9 ? normalized.substring(0, 9) : normalized;
  if (normalized.endsWith('-1')) return '${year}秋冬';
  if (normalized.endsWith('-2')) return '${year}春夏';
  return name.isEmpty ? normalized : name;
}

int? deadlineMs(Json a) {
  final raw = text(a, 'deadline');
  final date = DateTime.tryParse(raw);
  return date?.millisecondsSinceEpoch;
}

int? examMs(Json a) {
  final date = DateTime.tryParse(text(a, 'time'));
  return date?.millisecondsSinceEpoch;
}

bool isSubmitted(Json a) => a['submitted'] == true;

String formatDateTime(String raw) {
  final date = DateTime.tryParse(raw);
  if (date == null) return raw.isEmpty ? '未设置' : raw;
  final local = date.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String formatHms(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600, minutes = (safe % 3600) ~/ 60, rest = safe % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _monthName(int month) => const [
  'JANUARY',
  'FEBRUARY',
  'MARCH',
  'APRIL',
  'MAY',
  'JUNE',
  'JULY',
  'AUGUST',
  'SEPTEMBER',
  'OCTOBER',
  'NOVEMBER',
  'DECEMBER',
][month - 1];
String _weekday(int weekday) =>
    const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][weekday - 1];

String compressWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = [...weeks]..sort();
  final parts = <String>[];
  var start = sorted.first, end = sorted.first;
  for (final week in sorted.skip(1)) {
    if (week == end + 1) {
      end = week;
    } else {
      parts.add(start == end ? '$start' : '$start-$end');
      start = end = week;
    }
  }
  parts.add(start == end ? '$start' : '$start-$end');
  return parts.join(',');
}

String fileKind(String name) {
  final ext = name.toLowerCase().split('.').last;
  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(ext))
    return 'image';
  if (['txt', 'md', 'json', 'csv'].contains(ext)) return 'text';
  if (ext == 'pdf') return 'pdf';
  if (['doc', 'docx'].contains(ext)) return 'word';
  if (['ppt', 'pptx'].contains(ext)) return 'slides';
  if (['xls', 'xlsx'].contains(ext)) return 'sheet';
  if (['mp4', 'mov', 'avi'].contains(ext)) return 'video';
  if (['mp3', 'wav'].contains(ext)) return 'audio';
  if (['zip', 'rar', '7z'].contains(ext)) return 'archive';
  return 'file';
}

bool canPreview(String kind) => ['image', 'text', 'pdf'].contains(kind);
bool isOfficeDocument(String name) =>
    ['word', 'slides', 'sheet'].contains(fileKind(name));
IconData fileIcon(String kind) =>
    {
      'image': Icons.image_outlined,
      'text': Icons.article_outlined,
      'pdf': Icons.picture_as_pdf_outlined,
      'word': Icons.description_outlined,
      'slides': Icons.slideshow_outlined,
      'sheet': Icons.table_chart_outlined,
      'video': Icons.movie_outlined,
      'audio': Icons.audiotrack_outlined,
      'archive': Icons.archive_outlined,
    }[kind] ??
    Icons.insert_drive_file_outlined;
Color fileColor(String kind) =>
    {
      'image': const Color(0xff55447a),
      'text': ink,
      'pdf': seal,
      'word': blue,
      'slides': gold,
      'sheet': const Color(0xff2e7d32),
      'video': const Color(0xff2a5a5e),
      'audio': const Color(0xff8c3a2e),
      'archive': const Color(0xff8a5222),
    }[kind] ??
    ink;
