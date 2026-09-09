import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:html/parser.dart' as html;
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/services.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import 'chat.dart';
import 'export.dart';
import 'theme.dart';

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) {
    throw const AppError('INVALID_INPUT', '链接地址无效。');
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class FeaturePage extends StatefulWidget {
  const FeaturePage({super.key, required this.services, required this.page});
  final AppServices services;
  final String page;
  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> with WidgetsBindingObserver {
  late Future<Json> data;
  String semester = academicSemester(beijing(DateTime.now()));
  String filter = '待完成', query = '';
  final imageKey = GlobalKey();
  AppServices get s => widget.services;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    data = load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  void refresh() => setState(() => data = load(refresh: true));
  Future<Json> load({bool refresh = false}) async {
    switch (widget.page) {
      case '/courses':
        return {
          'timetable': (await s.campus.timetable(
            semester,
            refresh: refresh,
          )).map((e) => e.toJson()).toList(),
          'courses': await s.campus.courses(
            semesterId: semester,
            refresh: refresh,
          ),
          'semesters': await s.campus.semesters(),
        };
      case '/assignments':
        return {
          'items': await s.campus.assignments(
            semesterId: semester,
            refresh: refresh,
          ),
        };
      case '/exams':
        return {'items': await s.campus.exams(semester, refresh: refresh)};
      case '/school-info':
        return s.campus.notices();
      case '/downloads':
        return {'items': await s.db.list('downloads')};
      case '/classroom':
        return {};
      default:
        final result = <String, dynamic>{
          'settings': await s.db.get('settings', 'app') ?? {},
        };
        for (final entry in <String, Future<Object?> Function()>{
          'schedule': () => s.campus.upcoming(),
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
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: data,
    builder: (context, snapshot) {
      final titles = {
        '/': '工作台',
        '/courses': '课程表',
        '/assignments': '待办作业',
        '/exams': '考试安排',
        '/school-info': '学校信息',
        '/downloads': '下载',
        '/classroom': '智云课堂',
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titles[widget.page] ?? '工作台',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${isoDay(beijing(DateTime.now()))}  ·  求是创新',
            style: const TextStyle(color: gold, letterSpacing: 2),
          ),
          const SizedBox(height: 22),
          if (['/courses', '/assignments', '/exams'].contains(widget.page))
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField<String>(
                initialValue: semester,
                decoration: const InputDecoration(labelText: '学期'),
                items: [
                  for (final term in semesters())
                    DropdownMenuItem(
                      value: term,
                      child: Text('$term ${term.endsWith('-1') ? '秋冬' : '春夏'}'),
                    ),
                ],
                onChanged: (v) {
                  semester = v!;
                  refresh();
                },
              ),
            ),
          if (snapshot.connectionState != ConnectionState.done)
            const Paper(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (snapshot.hasError)
            Paper(
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
            )
          else
            ...content(snapshot.data ?? {}),
          if (s.campus.stale.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('网络暂不可用，部分内容来自本地缓存。', style: TextStyle(color: gold)),
            ),
        ],
      );
    },
  );
  List<String> semesters() {
    final year = beijing(DateTime.now()).year;
    return [
      for (var y = year; y >= year - 7; y--) ...[
        '$y-${y + 1}-1',
        '$y-${y + 1}-2',
      ],
    ];
  }

  List<Widget> content(Json d) {
    switch (widget.page) {
      case '/courses':
        final entries = rows(
          d['timetable'],
        ).map(TimetableEntry.fromJson).toList();
        return [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => act(() => exportPng(imageKey, semester)),
                icon: const Icon(Icons.image_outlined),
                label: const Text('导出图片'),
              ),
              OutlinedButton.icon(
                onPressed: () => act(() => exportXlsx(entries, semester)),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('导出 Excel'),
              ),
              OutlinedButton(
                onPressed: () => act(() async {
                  final grades = await s.campus.grades(semester);
                  if (mounted) {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => SizedBox(
                        height: MediaQuery.sizeOf(ctx).height * .8,
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            const Text('成绩与学分', style: TextStyle(fontSize: 24)),
                            for (final g in grades)
                              ListTile(
                                title: Text(text(g, 'courseName')),
                                subtitle: Text(
                                  '学分 ${g['credit']} · 绩点 ${g['fivePoint']}',
                                ),
                                trailing: Text(text(g, 'original')),
                              ),
                          ],
                        ),
                      ),
                    );
                  }
                }),
                child: const Text('成绩与学分'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RepaintBoundary(
              key: imageKey,
              child: TimetableView(entries: entries, semester: semester),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '课程目录',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          for (final c in rows(d['courses']))
            Paper(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.menu_book, color: blue),
                title: Text(text(c, 'name')),
                subtitle: Text(text(c, 'teachingClassName')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => courseDetail(c),
              ),
            ),
        ];
      case '/assignments':
        final work = rows(d['items']);
        final filtered = work
            .where(
              (a) =>
                  assignmentState(a) == filter &&
                  '${a['title']} ${a['courseName']}'.contains(query),
            )
            .toList();
        return [
          Wrap(
            spacing: 8,
            children: [
              for (final label in ['待完成', '已逾期', '已提交', '无截止'])
                ChoiceChip(
                  label: Text(label),
                  selected: filter == label,
                  onSelected: (_) => setState(() => filter = label),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            decoration: const InputDecoration(
              hintText: '搜索课程或作业',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 16),
          if (filtered.isEmpty) empty('暂无$filter作业'),
          for (final a in filtered)
            Paper(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(text(a, 'title')),
                subtitle: Text(
                  '${a['courseName']}\n截止：${a['deadline'] ?? '未设置'}',
                ),
                isThreeLine: true,
                onTap: () => assignmentDetail(a),
              ),
            ),
        ];
      case '/exams':
        final exams = rows(d['items']);
        return [
          if (exams.isEmpty) empty('本学期暂无考试安排'),
          for (final e in exams)
            Paper(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text(e, 'courseName'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('${e['time']}'),
                  Text(
                    '考场：${e['location'] ?? '未公布'}  ·  座位：${e['seat'] ?? '未公布'}',
                  ),
                ],
              ),
            ),
        ];
      case '/school-info':
        return [
          for (final error in d['failures'] as List? ?? [])
            Text('$error', style: const TextStyle(color: seal)),
          for (final n in rows(d['items']))
            Paper(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text(
                  '${n['important'] == true ? '[置顶] ' : ''}${n['title']}',
                ),
                subtitle: Text(
                  '${n['source'] == 'sztz' ? '素质拓展' : '教务通知'} · ${n['date']} · ${n['publisher'] ?? ''}',
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => act(() => openExternal(text(n, 'url'))),
              ),
            ),
        ];
      case '/downloads':
        return [
          if (rows(d['items']).isEmpty) empty('暂无下载记录'),
          for (final file in rows(d['items']))
            Paper(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.description_outlined,
                      color: blue,
                    ),
                    title: Text(text(file, 'fileName')),
                    subtitle: Text(
                      '${file['status']} · ${file['size'] ?? '—'} 字节',
                    ),
                    onTap: () => act(() async {
                      final f = await s.files.file(file);
                      final result = await OpenFilex.open(f.path);
                      if (result.type != ResultType.done) {
                        throw AppError('FILE_OPEN_FAILED', result.message);
                      }
                    }),
                  ),
                  Wrap(
                    spacing: 10,
                    children: [
                      TextButton(
                        onPressed: () => act(() async {
                          await s.files.delete(file);
                          refresh();
                        }),
                        child: const Text('移除记录'),
                      ),
                      TextButton(
                        onPressed: () => act(() async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除本地文件？'),
                              content: Text(text(file, 'fileName')),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true) {
                            await s.files.delete(file, purge: true);
                            refresh();
                          }
                        }),
                        child: const Text(
                          '删除文件',
                          style: TextStyle(color: seal),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ];
      case '/classroom':
        return [empty('智云课堂尚未开放')];
      default:
        return dashboard(d);
    }
  }

  Widget empty(String label) => Paper(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(label, style: const TextStyle(color: gold)),
      ),
    ),
  );
  List<Widget> dashboard(Json d) {
    final settings = object(d['settings'] ?? {}),
        events = rows((d['schedule'] as Map?)?['events'] ?? []);
    final work = rows(
      d['assignments'] ?? [],
    ).where((a) => a['submitted'] != true).toList();
    return [
      Paper(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${text(settings, 'nickname', '同学')}，展信佳。',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text('循着课表安排今日，从容完成每一件事。'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => openChat(context, s),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('问问求是助手'),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          for (final item in [
            ('在读课程', rows(d['courses'] ?? []).length),
            ('待办作业', work.length),
            ('考试安排', rows(d['exams'] ?? []).length),
          ])
            SizedBox(
              width: 200,
              child: Paper(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.$1, style: const TextStyle(color: gold)),
                    Text(
                      '${item.$2}',
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const Text(
        '壹 · 接下来 48 小时',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      if (d['scheduleError'] != null)
        Paper(child: Text('${d['scheduleError']}'))
      else if (events.isEmpty)
        empty('近期暂无日程'),
      for (final e in events)
        Paper(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              e['type'] == 'class'
                  ? Icons.menu_book
                  : e['type'] == 'exam'
                  ? Icons.edit_note
                  : Icons.checklist,
              color: blue,
            ),
            title: Text(text(e, 'title')),
            subtitle: Text(
              '${e['date']} ${e['startTime']}-${e['endTime']}  ${e['location'] ?? ''}',
            ),
          ),
        ),
      const SizedBox(height: 12),
      const Text(
        '贰 · 待办作业',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      if (d['assignmentsError'] != null)
        Paper(child: Text('${d['assignmentsError']}')),
      for (final a in work.take(6))
        Paper(
          padding: EdgeInsets.zero,
          child: ListTile(
            title: Text(text(a, 'title')),
            subtitle: Text('${a['courseName']} · ${a['deadline'] ?? '无截止时间'}'),
            onTap: () => assignmentDetail(a),
          ),
        ),
    ];
  }

  Future<void> assignmentDetail(Json a) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * .8,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(text(a, 'title'), style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 12),
          Text('${a['courseName']} · ${a['deadline'] ?? ''}'),
          const Divider(),
          MarkdownBody(
            data: html.parse(text(a, 'description')).body?.text ?? '',
          ),
          for (final f in rows(a['attachments'] ?? []))
            ListTile(
              title: Text(text(f, 'name')),
              trailing: const Icon(Icons.download),
              onTap: () => download({...f, 'courseId': a['courseId']}),
            ),
        ],
      ),
    ),
  );
  Future<void> courseDetail(Json c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .88,
        child: DefaultTabController(
          length: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  text(c, 'name'),
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: '课程资料'),
                  Tab(text: '作业'),
                  Tab(text: '小测'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    FutureList(
                      load: () => s.campus.materials(text(c, 'id')),
                      builder: (m) => ExpansionTile(
                        title: Text(text(m, 'title')),
                        children: [
                          for (final f in rows(m['files']))
                            ListTile(
                              title: Text(text(f, 'name')),
                              trailing: const Icon(Icons.download),
                              onTap: () =>
                                  download({...f, 'courseId': c['id']}),
                            ),
                        ],
                      ),
                    ),
                    FutureList(
                      load: () => s.campus.assignments(courseId: text(c, 'id')),
                      builder: (a) => ListTile(
                        title: Text(text(a, 'title')),
                        subtitle: Text(text(a, 'deadline')),
                        onTap: () => assignmentDetail(a),
                      ),
                    ),
                    FutureList(
                      load: () => s.campus.quizzes(text(c, 'id')),
                      builder: (q) => ListTile(
                        title: Text(text(q, 'title')),
                        subtitle: Text(text(q, 'deadline')),
                        onTap: () => act(() => openExternal(text(q, 'url'))),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> download(Json f) => act(() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载课程资料'),
        content: Text(text(f, 'name')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          if (RegExp(
            r'\.(docx?|pptx?|xlsx?)$',
            caseSensitive: false,
          ).hasMatch(text(f, 'name')))
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'pdf'),
              child: const Text('PDF 预览版'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'original'),
            child: const Text('下载原文件'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    await s.files.download({
      'courseId': f['courseId'],
      'fileId': f['id'],
      'fileName': f['name'],
      'officePdf': choice == 'pdf',
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文件已保存，可在下载页打开。')));
    }
  });
}

String assignmentState(Json a) {
  if (a['submitted'] == true) return '已提交';
  final deadline = DateTime.tryParse(text(a, 'deadline'));
  if (deadline == null) return '无截止';
  return deadline.isBefore(DateTime.now()) ? '已逾期' : '待完成';
}

class FutureList extends StatefulWidget {
  const FutureList({super.key, required this.load, required this.builder});
  final Future<List<Json>> Function() load;
  final Widget Function(Json) builder;
  @override
  State<FutureList> createState() => _FutureListState();
}

class _FutureListState extends State<FutureList> {
  late final future = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
    future: future,
    builder: (ctx, s) {
      if (s.hasError) return Center(child: Text('${s.error}'));
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      if (s.data!.isEmpty) return const Center(child: Text('暂无内容'));
      return ListView(children: s.data!.map(widget.builder).toList());
    },
  );
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
  Widget build(BuildContext context) => Container(
    width: 1050,
    color: paperCard,
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Text(
          '浙江大学课程表 · $semester',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(width: 70, child: Text('节次')),
            for (final name in ['一', '二', '三', '四', '五', '六', '日'])
              Expanded(child: Center(child: Text('周$name'))),
          ],
        ),
        const Divider(),
        SizedBox(
          height: 900,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 70,
                child: Column(
                  children: [
                    for (var section = 1; section <= 15; section++)
                      SizedBox(
                        height: 60,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$section'),
                            Text(
                              sessionTimes[section][0],
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              for (var weekday = 1; weekday <= 7; weekday++)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        for (var row = 0; row < 15; row++)
                          Positioned(
                            top: row * 60,
                            left: 0,
                            right: 0,
                            height: 60,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: ink.withValues(alpha: .07),
                                ),
                              ),
                            ),
                          ),
                        for (final e in entries.where(
                          (e) => e.weekday == weekday,
                        ))
                          Positioned(
                            top: (e.startSection - 1) * 60,
                            left: 2,
                            right: 2,
                            height:
                                (e.endSection - e.startSection + 1) * 60 - 2,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Color(
                                  courseColors[e.courseName.runes.fold(
                                        0,
                                        (a, b) => a + b,
                                      ) %
                                      courseColors.length],
                                ),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.courseName,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${e.location}\n${e.teacher}\n${e.subSemester}',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
