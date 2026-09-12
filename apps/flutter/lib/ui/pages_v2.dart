import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

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
String _weekdayName(int day) =>
    (day >= 1 && day <= 7) ? _dayNames[day - 1] : '$day';

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !['http', 'https'].contains(uri.scheme)) {
    throw const AppError('INVALID_INPUT', '链接地址无效。');
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw const AppError('SERVICE_UNAVAILABLE', '无法打开外部链接。');
  }
}

String? dataUpdatedLabel(String? raw) {
  final time = raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  if (time == null) return null;
  final minutes = DateTime.now().toUtc().difference(time).inMinutes;
  return '数据更新于 ${minutes < 0 ? 0 : minutes} 分钟前';
}

class FeaturePage extends StatefulWidget {
  const FeaturePage({
    super.key,
    required this.services,
    required this.page,
    this.initialAssignmentTab,
  });
  final AppServices services;
  final String page;
  final String? initialAssignmentTab;

  @override
  State<FeaturePage> createState() => _FeaturePageState();
}

class _FeaturePageState extends State<FeaturePage> {
  late Future<Json> data;
  Future<Json>? overviewData;
  String semester = academicSemester(beijing(DateTime.now()));
  String overviewSemester = 'all';
  String assignmentTab = 'all';
  String noticeSource = 'all';
  String upcomingTab = 'schedule';
  int urgentHours = 24;
  DateTime now = DateTime.now();
  Timer? ticker;
  bool _refreshing = false;
  bool _refreshingTimetable = false;
  bool _refreshingOverview = false;
  bool _loadingPageData = false;
  bool _loadingOverviewData = false;
  StreamSubscription<String>? _cacheSubscription;
  Timer? _pageReloadTimer;
  Timer? _overviewReloadTimer;
  final exportKey = GlobalKey();
  bool _exporting = false;

  AppServices get s => widget.services;

  bool get hasRightPanel => widget.page == '/courses';

  void _syncPageContext({Json? activeCourse, String? courseTab}) {
    final ctx = _buildPageContext(
      activeCourse: activeCourse,
      courseTab: courseTab,
    );
    s.updatePageContext(ctx);
  }

  PageContext _buildPageContext({Json? activeCourse, String? courseTab}) {
    switch (widget.page) {
      case '/courses':
        return PageContext.courses(
          timetableSemester: semester,
          overviewSemester: overviewSemester,
          activeCourse: activeCourse,
          courseTab: courseTab,
        );
      case '/assignments':
        return PageContext.assignments(
          tab: assignmentTab,
          urgentHours: urgentHours,
        );
      case '/exams':
        return PageContext.exams(semester: semester);
      case '/school-info':
        return PageContext.schoolInfo(source: noticeSource);
      case '/downloads':
        return PageContext.downloads();
      case '/classroom':
        return PageContext.classroom();
      default:
        return PageContext.dashboard();
    }
  }

  @override
  void initState() {
    super.initState();
    final initialTab =
        widget.initialAssignmentTab ??
        (s.targetAssignmentTab != 'all' ? s.targetAssignmentTab : null);
    if (initialTab != null && initialTab.isNotEmpty) {
      assignmentTab = initialTab;
      s.targetAssignmentTab = 'all';
    }
    _syncPageContext();
    _cacheSubscription = s.campus.cacheChanges.listen(_handleCacheChange);
    data = _loadPageData(refresh: s.claimInitialRefresh(widget.page));
    if (widget.page == '/courses') {
      overviewData = _loadOverviewData(
        refresh: s.claimInitialRefresh('/courses:panel'),
      );
    }
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(FeaturePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final targetTab =
        widget.initialAssignmentTab ??
        (s.targetAssignmentTab != 'all' ? s.targetAssignmentTab : null);
    if (targetTab != null && targetTab.isNotEmpty) {
      if (assignmentTab != targetTab) {
        setState(() {
          assignmentTab = targetTab;
          s.targetAssignmentTab = 'all';
        });
        _syncPageContext();
      }
    }
    if (oldWidget.page != widget.page) {
      _syncPageContext();
    }
  }

  @override
  void dispose() {
    ticker?.cancel();
    _cacheSubscription?.cancel();
    _pageReloadTimer?.cancel();
    _overviewReloadTimer?.cancel();
    super.dispose();
  }

  Future<Json> _loadPageData({bool refresh = false}) async {
    _loadingPageData = true;
    try {
      return await load(refresh: refresh);
    } finally {
      _loadingPageData = false;
    }
  }

  Future<Json> _loadOverviewData({bool refresh = false}) async {
    _loadingOverviewData = true;
    try {
      return await loadCourseOverview(s, semester, refresh: refresh);
    } finally {
      _loadingOverviewData = false;
    }
  }

  bool _mainPageUsesCache(String key) {
    switch (widget.page) {
      case '/':
        return key == 'semesters' ||
            key == 'courses' ||
            key == 'grades:' ||
            key == 'enrolled_courses:all' ||
            key.startsWith('calendar:') ||
            key.startsWith('timetable:') ||
            key.startsWith('exams:') ||
            key.startsWith('assignments:');
      case '/courses':
        return key == 'semesters' || key.startsWith('timetable:');
      case '/assignments':
        return key == 'courses' || key.startsWith('assignments:');
      case '/exams':
        return key == 'semesters' || key.startsWith('exams:');
      case '/school-info':
        return key.startsWith('notices:');
      default:
        return false;
    }
  }

  bool _overviewUsesCache(String key) {
    if (widget.page != '/' && widget.page != '/courses') return false;
    return key == 'semesters' ||
        key == 'courses' ||
        key == 'grades:' ||
        key == 'enrolled_courses:all' ||
        key.startsWith('timetable:');
  }

  void _handleCacheChange(String key) {
    if (!mounted) return;
    if (!_loadingPageData && _mainPageUsesCache(key)) _schedulePageReload();
    if (!_loadingOverviewData &&
        overviewData != null &&
        _overviewUsesCache(key)) {
      _scheduleOverviewReload();
    }
  }

  void _schedulePageReload() {
    if (_pageReloadTimer != null) return;
    _pageReloadTimer = Timer(const Duration(milliseconds: 120), () {
      _pageReloadTimer = null;
      unawaited(_reloadPageFromCache());
    });
  }

  Future<void> _reloadPageFromCache() async {
    if (!mounted || _loadingPageData) return;
    final previous = data;
    final next = _loadPageData();
    setState(() => data = next);
    try {
      await next;
    } catch (_) {
      if (mounted && identical(data, next)) setState(() => data = previous);
    }
  }

  void _scheduleOverviewReload() {
    if (_overviewReloadTimer != null) return;
    _overviewReloadTimer = Timer(const Duration(milliseconds: 120), () {
      _overviewReloadTimer = null;
      unawaited(_reloadOverviewFromCache());
    });
  }

  Future<void> _reloadOverviewFromCache() async {
    if (!mounted || _loadingOverviewData || overviewData == null) return;
    final previous = overviewData!;
    final next = _loadOverviewData();
    if (mounted) setState(() => overviewData = next);
    try {
      await next;
    } catch (_) {
      if (mounted && identical(overviewData, next)) {
        setState(() => overviewData = previous);
      }
    }
  }

  Future<void> refresh({bool force = true}) async {
    if (widget.page == '/courses') {
      await refreshTimetable(force: force);
      return;
    }
    if (_refreshing) return;
    _refreshing = true;
    final next = _loadPageData(refresh: force);
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

  Future<void> refreshTimetable({bool force = true}) async {
    if (_refreshingTimetable) return;
    _refreshingTimetable = true;
    final next = _loadPageData(refresh: force);
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
      _refreshingTimetable = false;
    }
  }

  Future<void> _exportTimetablePng() async {
    if (!mounted) return;
    setState(() => _exporting = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      await exportPng(exportKey, semester);
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> refreshOverview() async {
    if (_refreshingOverview) return;
    _refreshingOverview = true;
    final next = _loadOverviewData(refresh: true);
    if (mounted) {
      setState(() {
        overviewData = next;
      });
    }
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the page error; refresh controls should settle.
    } finally {
      _refreshingOverview = false;
    }
  }

  Future<Json> loadOverview({bool refresh = false}) =>
      _loadOverviewData(refresh: refresh);

  Future<Json> load({bool refresh = false}) async {
    switch (widget.page) {
      case '/courses':
        final semesters = await s.campus.semesters(refresh: refresh);
        final timetable = (await s.campus.timetable(
          semester,
          refresh: refresh,
        )).map((e) => e.toJson()).toList();
        return {
          'semesters': semesters,
          'timetable': timetable,
          '_updatedAt': await _updatedAt(
            cacheKeys: ['semesters', 'timetable:$semester'],
          ),
        };
      case '/assignments':
        final courseCandidates = await s.campus.courses(refresh: refresh);
        final items = await s.campus.assignments(
          courseCandidates: courseCandidates,
          refresh: refresh,
        );
        final assignmentCacheKeys = courseCandidates
            .map((course) => text(course, 'id').trim())
            .where((courseId) => courseId.isNotEmpty)
            .map((courseId) => 'assignments:$courseId');
        return {
          'items': items,
          '_updatedAt': await _updatedAt(
            cacheKeys: ['courses', ...assignmentCacheKeys],
          ),
        };
      case '/exams':
        final items = await s.campus.exams(semester, refresh: refresh);
        final semesters = await s.campus.semesters(refresh: refresh);
        return {
          'items': items,
          'semesters': semesters,
          '_updatedAt': await _updatedAt(
            cacheKeys: ['exams:$semester', 'semesters'],
          ),
        };
      case '/school-info':
        return s.campus.notices(refresh: refresh);
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
        Json? upcomingData;
        try {
          // upcoming() already loads the calendar, timetable, exams and
          // assignments needed by the dashboard. Keep this result as the
          // shared source for the cards instead of fetching each dataset
          // again below.
          upcomingData = await s.campus.upcoming(refresh: refresh);
          result['schedule'] = upcomingData;
          result['assignments'] = rows(upcomingData['assignments'] ?? []);
          result['exams'] = rows(upcomingData['currentExams'] ?? []);
        } on AppError catch (e) {
          result['scheduleError'] = e.message;
        }

        try {
          final schedule = upcomingData;
          result['courseOverview'] = await loadCourseOverview(
            s,
            semester,
            refresh: refresh,
            semestersOverride: schedule == null
                ? null
                : rows(schedule['semesters'] ?? []),
            rawCoursesOverride: schedule == null
                ? null
                : rows(schedule['courses'] ?? []),
            timetableOverride: schedule == null
                ? null
                : rows(
                    schedule['currentTimetable'] ?? [],
                  ).map(TimetableEntry.fromJson).toList(),
          );
        } on AppError catch (e) {
          result['courseOverviewError'] = e.message;
        }
        result['campusStatus'] = hasCampusCredential
            ? s.campus.session.authStatus
            : 'missing';
        final relevantSemesters = <String>{semester};
        final semesterIds = upcomingData?['semesterIds'];
        if (semesterIds is List) {
          relevantSemesters.addAll(
            semesterIds
                .map((value) => '$value'.trim())
                .where((value) => value.isNotEmpty),
          );
        }
        final assignmentCacheKeys = <String>{};
        final assignmentCourseIds = upcomingData?['assignmentCourseIds'];
        if (assignmentCourseIds is List) {
          assignmentCacheKeys.addAll(
            assignmentCourseIds
                .map((value) => '$value'.trim())
                .where((value) => value.isNotEmpty)
                .map((value) => 'assignments:$value'),
          );
        }
        result['_updatedAt'] = await _updatedAt(
          cacheKeys: [
            'semesters',
            'courses',
            'enrolled_courses:all',
            'grades:',
            ...assignmentCacheKeys,
            for (final id in relevantSemesters) ...[
              'timetable:$id',
              'exams:$id',
            ],
          ],
          calendarKeys: relevantSemesters,
        );
        return result;
    }
  }

  Future<String?> _updatedAt({
    Iterable<String> cacheKeys = const [],
    Iterable<String> cachePrefixes = const [],
    Iterable<String> calendarKeys = const [],
  }) async {
    final time = await s.campus.oldestUpdatedAt(
      cacheKeys: cacheKeys,
      cachePrefixes: cachePrefixes,
      calendarKeys: calendarKeys,
    );
    return time?.toIso8601String();
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
      onRefresh: widget.page == '/courses' ? refreshTimetable : refresh,
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
        onRefresh: widget.page == '/courses' ? refreshOverview : refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: _rightPanelContent(),
        ),
      ),
    ),
  );

  Widget _rightPanelContent({VoidCallback? onPanelChanged}) =>
      FutureBuilder<Json>(
        future: widget.page == '/courses'
            ? (overviewData ??= loadOverview(
                refresh: s.claimInitialRefresh('/courses:panel'),
              ))
            : data,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: blue),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, color: seal),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error is AppError
                          ? (snapshot.error as AppError).message
                          : '课程加载失败',
                      style: const TextStyle(color: ink, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        refreshOverview();
                        onPanelChanged?.call();
                      },
                      child: const Text('重试', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) return const SizedBox.shrink();
          final d = snapshot.data!;
          switch (widget.page) {
            case '/courses':
              return CourseRightPanel(
                data: d,
                selected: overviewSemester,
                refreshing: _refreshingOverview,
                onChanged: (value) {
                  setState(() => overviewSemester = value);
                  _syncPageContext();
                  onPanelChanged?.call();
                },
                onRefresh: () {
                  refreshOverview();
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
                  _syncPageContext();
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
          onRefresh: () async {
            await refreshOverview();
            setSheetState(() {});
          },
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

  Future<void> _openCourseOverviewSheet({String? initialSemester}) {
    if (initialSemester != null) {
      overviewSemester = initialSemester;
    } else if (overviewSemester.isEmpty) {
      overviewSemester = semester;
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: paperCard,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .85,
          child: RefreshIndicator(
            color: blue,
            backgroundColor: paperCard,
            onRefresh: () async {
              await refreshOverview();
              setSheetState(() {});
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: FutureBuilder<Json>(
                future: overviewData ??= loadOverview(
                  refresh: s.claimInitialRefresh('/courses:panel'),
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: blue),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cloud_off, color: seal),
                            const SizedBox(height: 8),
                            Text(
                              snapshot.error is AppError
                                  ? (snapshot.error as AppError).message
                                  : '课程总览加载失败',
                              style: const TextStyle(color: ink, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () {
                                refreshOverview();
                                setSheetState(() {});
                              },
                              child: const Text(
                                '重试',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final d = snapshot.data!;
                  final choices = semesterChoices(rows(d['semesters'] ?? []));
                  var curSelected = overviewSemester;
                  if (!choices.any((c) => c.id == curSelected)) {
                    final activeChoice = choices.firstWhere(
                      (c) => c.id == semester,
                      orElse: () => choices.first,
                    );
                    curSelected = activeChoice.id;
                    overviewSemester = curSelected;
                  }
                  return CourseRightPanel(
                    data: d,
                    selected: curSelected,
                    refreshing: _refreshingOverview,
                    onChanged: (value) {
                      setState(() => overviewSemester = value);
                      _syncPageContext();
                      setSheetState(() {});
                    },
                    onRefresh: () {
                      refreshOverview();
                      setSheetState(() {});
                    },
                    onSelect: (course) {
                      Navigator.of(ctx).pop();
                      courseDetail(course);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    final choices = widget.page == '/courses'
        ? semesterChoices(
            rows(snapshot.data?['semesters'] ?? []),
            includeAll: false,
          )
        : widget.page == '/exams'
        ? semesterChoices(rows(snapshot.data?['semesters'] ?? []))
        : const <SemesterChoice>[];
    if (widget.page == '/courses' && choices.isNotEmpty && semester == 'all') {
      semester = choices.first.id;
    }
    final isBusy = widget.page == '/courses'
        ? _refreshingTimetable
        : _refreshing;
    final body = <Widget>[
      PageHead(
        title: title,
        titleSuffix: null,
        subtitle: subtitle,
        updatedAt: snapshot.hasData
            ? dataUpdatedLabel(text(snapshot.data!, '_updatedAt'))
            : null,
        trailing: widget.page == '/courses'
            ? null
            : IconButton(
                onPressed: isBusy ? null : refresh,
                tooltip: widget.page == '/school-info' ? '刷新通知' : '刷新',
                icon: isBusy
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
      ),
      if (choices.isNotEmpty && widget.page == '/exams')
        _semesterPicker(choices),
      if (widget.page == '/assignments' && snapshot.hasData)
        Paper(
          child: AssignmentRightPanel(
            data: snapshot.data!,
            hours: urgentHours,
            onHoursChanged: (value) {
              setState(() => urgentHours = value);
              _syncPageContext();
            },
          ),
        ),
      _asyncBody(snapshot, wide: wide, choices: choices),
      if (s.campus.stale.isNotEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('网络暂不可用，部分内容来自本地缓存。', style: TextStyle(color: gold)),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: body);
  }

  Widget _semesterPicker(List<SemesterChoice> choices) {
    if (choices.isEmpty) return const SizedBox.shrink();
    final activeId = choices.any((c) => c.id == semester)
        ? semester
        : choices.first.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final choice in choices)
                _examSemesterTab(choice, isSelected: choice.id == activeId),
            ],
          );
        },
      ),
    );
  }

  Widget _examSemesterTab(SemesterChoice choice, {required bool isSelected}) {
    return InkWell(
      onTap: () {
        if (choice.id != semester) {
          setState(() => semester = choice.id);
          _syncPageContext();
          refresh(force: false);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? blue : paperCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? blue : ink.withValues(alpha: .2),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: blue.withValues(alpha: .2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          choice.id == 'all' ? '全部学期' : choice.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? paperCard : ink,
          ),
        ),
      ),
    );
  }

  Widget _asyncBody(
    AsyncSnapshot<Json> snapshot, {
    required bool wide,
    List<SemesterChoice> choices = const [],
  }) {
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
      children: content(snapshot.data ?? {}, wide: wide, choices: choices),
    );
  }

  List<Widget> content(
    Json d, {
    required bool wide,
    List<SemesterChoice> choices = const [],
  }) {
    switch (widget.page) {
      case '/courses':
        return _courses(d, wide: wide, choices: choices);
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

  List<Widget> _courses(
    Json d, {
    required bool wide,
    List<SemesterChoice> choices = const [],
  }) {
    final entries = rows(d['timetable']).map(TimetableEntry.fromJson).toList();
    return [
      RepaintBoundary(
        key: exportKey,
        child: TimetableView(
          entries: entries,
          semester: semester,
          wide: wide,
          choices: choices,
          refreshing: _refreshingTimetable,
          isExporting: _exporting,
          onSemesterChanged: (id) {
            setState(() {
              semester = id;
            });
            _syncPageContext();
            refreshTimetable(force: false);
          },
          onExportPng: () => act(_exportTimetablePng),
          onExportXlsx: () => act(() => exportXlsx(entries, semester)),
          onRefresh: refreshTimetable,
          onSelectCourse: _openTimetableCourse,
        ),
      ),
    ];
  }

  List<Widget> _assignments(Json d) {
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
                    _syncPageContext();
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
                onSelected: (_) {
                  setState(() => noticeSource = choice.$1);
                  _syncPageContext();
                },
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
    final rawAssignments = rows(d['assignments'] ?? []);
    final activeAssignments = rawAssignments
        .where((a) => isVisibleAssignment(a, now.millisecondsSinceEpoch))
        .toList();
    final pending = activeAssignments
        .where((a) => a['submitted'] != true)
        .toList();
    final assignments48h = pending.where((a) {
      final due = deadlineMs(a);
      return due != null &&
          due <= now.millisecondsSinceEpoch + 48 * 3600 * 1000 &&
          due >= now.millisecondsSinceEpoch;
    }).toList();
    final exams = rows(d['exams'] ?? []);
    final courseOverview = object(d['courseOverview'] ?? {});
    final overviewSemesters = rows(courseOverview['semesters'] ?? []);
    final overviewCourses = rows(courseOverview['courses'] ?? []);
    final currentCourses = coursesForSemester(
      overviewCourses,
      overviewSemesters,
      semester,
    );
    final allGrades = rows(courseOverview['grades'] ?? []);

    final nowMs = now.millisecondsSinceEpoch;
    final threshold = nowMs + urgentHours * 3600 * 1000;
    final urgentAssignments = activeAssignments
        .where(
          (a) =>
              !isSubmitted(a) &&
              deadlineMs(a) != null &&
              deadlineMs(a)! > nowMs &&
              deadlineMs(a)! <= threshold,
        )
        .toList();
    final relaxedAssignments = activeAssignments
        .where(
          (a) =>
              !isSubmitted(a) &&
              (deadlineMs(a) == null || deadlineMs(a)! > threshold),
        )
        .toList();
    final submittedAssignments = activeAssignments.where(isSubmitted).toList();

    final currentSemesterCredits = courseCredits(currentCourses);
    final gradeStats = GradeStats.compute(
      grades: allGrades,
      currentSemester: '',
      timetableCredits: currentSemesterCredits,
    );

    final dateInfo = object(schedule['dateInfo'] ?? {});
    final name = text(settings, 'nickname').trim().isEmpty
        ? '浙大学子'
        : text(settings, 'nickname');
    final avatarDataUrl = text(settings, 'avatarDataUrl');
    final campusStatus = text(d, 'campusStatus', 'missing');
    return [
      _dashboardHeader(
        name,
        dateInfo,
        campusStatus,
        avatarDataUrl,
        dataUpdatedLabel(text(d, '_updatedAt')),
      ),
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
        courses: currentCourses.length,
        semesterCredits: gradeStats.semesterCredits,
        exams: exams.length,
        urgentCount: urgentAssignments.length,
        relaxedCount: relaxedAssignments.length,
        submittedCount: submittedAssignments.length,
        gradeStats: gradeStats,
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
    String? updatedLabel,
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
                  if (updatedLabel != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      updatedLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: ink.withValues(alpha: .58),
                      ),
                    ),
                  ],
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
        onTap: () => _openEventCourse(event),
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

  Widget _dashboardAssignments(List<Json> assignments) {
    if (assignments.isEmpty) {
      return Paper(
        child: const PageEmpty(
          icon: 'checklist-paper',
          title: '近四十八小时暂无紧急待交作业',
          description: '所有待办作业均在安全期内或已全部提交完毕。',
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
            for (final a in assignments)
              SizedBox(width: width, child: _assignmentCard(a)),
          ],
        );
      },
    );
  }

  Widget _kpiRow({
    required int courses,
    required double semesterCredits,
    required int exams,
    required int urgentCount,
    required int relaxedCount,
    required int submittedCount,
    required GradeStats gradeStats,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 4
          : constraints.maxWidth >= 560
          ? 2
          : 1;
      const gap = 6.0;
      const cardHeight = 136.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

      final creditDisplay = semesterCredits > 0
          ? (semesterCredits == semesterCredits.roundToDouble()
                ? semesterCredits.toInt().toString()
                : semesterCredits.toStringAsFixed(1))
          : (courses > 0 ? '--' : '0');

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: width,
            height: cardHeight,
            child: MultiMetricKpi(
              label: '本学期学业',
              icon: 'book-open',
              items: [
                MultiMetricItem(
                  value: '$courses',
                  label: '课程数',
                  tooltip: '弹出辅助栏课程总览',
                  onTap: () {
                    overviewSemester = semester;
                    _openCourseOverviewSheet();
                  },
                ),
                MultiMetricItem(
                  value: creditDisplay,
                  label: '学分数',
                  tooltip: '本学期已选学分',
                  onTap: null,
                ),
                MultiMetricItem(
                  value: '$exams',
                  label: '考试数',
                  tooltip: '查看考试安排与考签',
                  onTap: () => context.go('/exams'),
                ),
              ],
            ),
          ),
          SizedBox(
            width: width,
            height: cardHeight,
            child: MultiMetricKpi(
              label: '待办作业',
              icon: 'checklist-paper',
              items: [
                MultiMetricItem(
                  value: '$urgentCount',
                  label: '将截止',
                  valueColor: urgentCount > 0 ? seal : null,
                  tooltip: '48小时内截止的待办作业',
                  onTap: () {
                    s.targetAssignmentTab = 'urgent';
                    context.go('/assignments?tab=urgent');
                  },
                ),
                MultiMetricItem(
                  value: '$relaxedCount',
                  label: '还不急',
                  tooltip: '安全期内的待办作业',
                  onTap: () {
                    s.targetAssignmentTab = 'relaxed';
                    context.go('/assignments?tab=relaxed');
                  },
                ),
                MultiMetricItem(
                  value: '$submittedCount',
                  label: '已提交',
                  valueColor: const Color(0xff2e7d32),
                  tooltip: '已提交完成的作业',
                  onTap: () {
                    s.targetAssignmentTab = 'submitted';
                    context.go('/assignments?tab=submitted');
                  },
                ),
              ],
            ),
          ),
          SizedBox(
            width: width,
            height: cardHeight,
            child: MultiMetricKpi(
              label: '学业成绩',
              icon: 'area-chart',
              items: [
                MultiMetricItem(
                  value: gradeStats.hasData && gradeStats.gpa > 0
                      ? gradeStats.gpa.toStringAsFixed(2)
                      : '--',
                  label: '目前总绩点',
                  tooltip: '五分制加权绩点 (GPA)，点击查看学业总览',
                  onTap: () {
                    overviewSemester = 'all';
                    _openCourseOverviewSheet(initialSemester: 'all');
                  },
                ),
                MultiMetricItem(
                  value: gradeStats.hasData
                      ? (gradeStats.totalEarnedCredits ==
                                gradeStats.totalEarnedCredits.roundToDouble()
                            ? gradeStats.totalEarnedCredits.toInt().toString()
                            : gradeStats.totalEarnedCredits.toStringAsFixed(1))
                      : '--',
                  label: '获得总学分',
                  tooltip: '累计获得有效学分，点击查看学业总览',
                  onTap: () {
                    overviewSemester = 'all';
                    _openCourseOverviewSheet(initialSemester: 'all');
                  },
                ),
                MultiMetricItem(
                  value: gradeStats.hasData && gradeStats.averageScore > 0
                      ? gradeStats.averageScore.toStringAsFixed(1)
                      : '--',
                  label: '百分制均分',
                  tooltip: '百分制加权平均分，点击查看学业总览',
                  onTap: () {
                    overviewSemester = 'all';
                    _openCourseOverviewSheet(initialSemester: 'all');
                  },
                ),
              ],
            ),
          ),
          SizedBox(
            width: width,
            height: cardHeight,
            child: Kpi(
              label: '下载中心',
              value: '本地文库',
              unit: '',
              foot: '',
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

  Future<void> courseDetail(Json c) async {
    final enriched = await _enrichCourse(c);
    if (!mounted) return;
    _syncPageContext(activeCourse: enriched, courseTab: 'materials');
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: paperCard,
        builder: (ctx) => CourseDetailSheet(
          services: s,
          course: enriched,
          onDownload: downloadFile,
          onPreview: previewFile,
          onAssignmentDetail: assignmentDetail,
          onTabChanged: (tab) {
            _syncPageContext(activeCourse: enriched, courseTab: tab);
          },
        ),
      );
    } finally {
      _syncPageContext();
    }
  }

  Future<Json> _enrichCourse(Json c) async {
    final name = text(c, 'name');
    final teacher = text(c, 'teacher');
    final location = text(c, 'location');
    final scheduleTime = text(c, 'scheduleTime');
    if (teacher.isNotEmpty && location.isNotEmpty && scheduleTime.isNotEmpty) {
      return c;
    }

    List<TimetableEntry> ttEntries = [];
    try {
      final d = await data;
      if (d['timetable'] is List) {
        ttEntries = rows(d['timetable']).map(TimetableEntry.fromJson).toList();
      }
    } catch (_) {}
    if (ttEntries.isEmpty) {
      try {
        final cached = await s.db.get('cache', 'timetable:$semester');
        if (cached != null) {
          ttEntries = rows(
            cached['items'],
          ).map(TimetableEntry.fromJson).toList();
        }
      } catch (_) {}
    }

    final cleanName = name.replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
    TimetableEntry? matched;
    for (final e in ttEntries) {
      if (e.courseName == name) {
        matched = e;
        break;
      }
    }
    if (matched == null) {
      for (final e in ttEntries) {
        final eClean = e.courseName
            .replaceAll(RegExp(r'[（\(].*?[）\)]'), '')
            .trim();
        if (eClean == cleanName ||
            e.courseName.contains(cleanName) ||
            cleanName.contains(e.courseName)) {
          matched = e;
          break;
        }
      }
    }

    if (matched == null) return c;

    final weekText = matched.weeks.isNotEmpty
        ? '${compressWeeks(matched.weeks)} 周'
        : '';
    final subText = matched.subSemester.isNotEmpty
        ? '${matched.subSemester} '
        : '';
    final timeStr =
        '周${_weekdayName(matched.weekday)} ${matched.startSection}-${matched.endSection}节 ($subText$weekText)';

    return {
      ...c,
      if (teacher.isEmpty && matched.teacher.isNotEmpty)
        'teacher': matched.teacher,
      if (location.isEmpty && matched.location.isNotEmpty)
        'location': matched.location,
      if (scheduleTime.isEmpty) 'scheduleTime': timeStr,
      if ((double.tryParse('${c['credit']}') ?? 0.0) <= 0 && matched.credit > 0)
        'credit': matched.credit,
    };
  }

  Future<void> _openTimetableCourse(TimetableEntry entry) async {
    List<Json> coursesList = [];
    try {
      final od = await overviewData;
      if (od != null) coursesList = rows(od['courses'] ?? []);
    } catch (_) {}
    if (coursesList.isEmpty) {
      try {
        final cached = await s.db.get('cache', 'courses');
        if (cached != null) coursesList = rows(cached['items']);
      } catch (_) {}
    }
    final matched = _findCourseByName(coursesList, entry.courseName);
    final weekText = entry.weeks.isNotEmpty
        ? '${compressWeeks(entry.weeks)} 周'
        : '';
    final subText = entry.subSemester.isNotEmpty ? '${entry.subSemester} ' : '';
    final timeStr =
        '周${_weekdayName(entry.weekday)} ${entry.startSection}-${entry.endSection}节 ($subText$weekText)';
    final enriched = {
      ...?matched,
      'name': entry.courseName,
      if (entry.teacher.isNotEmpty) 'teacher': entry.teacher,
      if (entry.location.isNotEmpty) 'location': entry.location,
      'scheduleTime': timeStr,
      if (entry.credit > 0) 'credit': entry.credit,
      if (matched == null || matched['learningZjuCreated'] == false)
        'learningZjuCreated': false,
    };
    await courseDetail(enriched);
  }

  Future<void> _openEventCourse(Json event) async {
    final name = text(event, 'title', text(event, 'courseName'));
    if (name.isEmpty) return;
    List<Json> coursesList = [];
    try {
      final d = await data;
      coursesList = rows(d['courses'] ?? []);
    } catch (_) {}
    if (coursesList.isEmpty) {
      try {
        final cached = await s.db.get('cache', 'courses');
        if (cached != null) coursesList = rows(cached['items']);
      } catch (_) {}
    }
    final matched = _findCourseByName(coursesList, name);
    final timeStr =
        '${text(event, 'date')} ${text(event, 'startTime')}-${text(event, 'endTime')}';
    final enriched = {
      ...?matched,
      'name': name,
      if (text(event, 'teacher').isNotEmpty) 'teacher': text(event, 'teacher'),
      if (text(event, 'location').isNotEmpty)
        'location': text(event, 'location'),
      'scheduleTime': timeStr,
      if (matched == null || matched['learningZjuCreated'] == false)
        'learningZjuCreated': false,
    };
    await courseDetail(enriched);
  }

  static Json? _findCourseByName(List<Json> courses, String name) {
    if (name.isEmpty) return null;
    final cleanName = name.replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
    for (final c in courses) {
      final cName = text(c, 'name');
      if (cName == name) return c;
    }
    for (final c in courses) {
      final cName = text(
        c,
        'name',
      ).replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
      if (cName == cleanName) return c;
    }
    for (final c in courses) {
      final cName = text(c, 'name');
      if (cName.contains(cleanName) || cleanName.contains(cName)) return c;
    }
    return null;
  }

  Future<void> downloadFile(Json f) async {
    await act(() async {
      await s.files.download({
        'courseId': text(f, 'courseId'),
        'fileId': text(f, 'id', text(f, 'fileId')),
        'fileName': text(f, 'name', text(f, 'fileName')),
        'courseName': text(f, 'courseName'),
        'officePdf': false,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('文件已保存，可在下载页打开。')));
      }
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

Set<String> matchingSemesterIds(List<Json> semesters, String selected) {
  final ids = <String>{selected};
  for (final semester in semesters) {
    final rawId = text(semester, 'id').trim();
    final normalizedName = semesterToId(text(semester, 'name'));
    final normalizedId = semesterToId(rawId);
    if (rawId == selected ||
        normalizedName == selected ||
        normalizedId == selected) {
      if (rawId.isNotEmpty) ids.add(rawId);
      if (normalizedName != null) ids.add(normalizedName);
      if (normalizedId != null) ids.add(normalizedId);
    }
  }
  final normalizedSelected = semesterToId(selected);
  if (normalizedSelected != null) ids.add(normalizedSelected);
  return ids;
}

List<Json> coursesForSemester(
  List<Json> allCourses,
  List<Json> semesters,
  String selected,
) {
  if (selected == 'all') return allCourses;
  final matchingIds = matchingSemesterIds(semesters, selected);
  return allCourses.where((course) {
    final semesterId = text(course, 'semesterId').trim();
    final semester = text(course, 'semester').trim();
    final normalizedSemesterId = semesterToId(semesterId) ?? semesterId;
    final normalizedSemester = semesterToId(semester) ?? semester;
    return matchingIds.contains(semesterId) ||
        matchingIds.contains(semester) ||
        matchingIds.contains(normalizedSemesterId) ||
        matchingIds.contains(normalizedSemester);
  }).toList();
}

double courseCredits(Iterable<Json> courses) => courses.fold<double>(
  0,
  (total, course) => total + (double.tryParse('${course['credit']}') ?? 0.0),
);

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
    final panelStats = _computePanelStats(
      selected: selected,
      courses: courses,
      allCourses: allCourses,
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
        _buildSemesterTabs(context, choices),
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
                  ..sort((a, b) => text(a, 'name').compareTo(text(b, 'name')))))
              _buildCourseItem(course),
          ],
      ],
    );
  }

  Widget _buildCourseItem(Json course) {
    final teacher = text(course, 'teacher');
    final creditVal = double.tryParse('${course['credit']}') ?? 0.0;
    final score = text(course, 'score', text(course, 'original')).trim();
    final gpa = text(course, 'gpa', text(course, 'fivePoint')).trim();
    final gradeBadge = formatGradeBadge(score, gpa);
    final isLearningCreated =
        course['learningZjuCreated'] == true ||
        (course['learningZjuCreated'] != false &&
            text(course, 'id').isNotEmpty &&
            !text(course, 'id').startsWith('(') &&
            int.tryParse(text(course, 'id')) != null);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => onSelect(course),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            side: BorderSide(color: ink.withValues(alpha: .12)),
          ),
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
                  if (!isLearningCreated) ...[
                    const SizedBox(width: 6),
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
                        '未建课',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: ink.withValues(alpha: .5),
                          fontWeight: FontWeight.w500,
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
                          color: isLearningCreated
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
                              color: isLearningCreated
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
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: ink.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${creditVal.toStringAsFixed(creditVal.truncateToDouble() == creditVal ? 0 : 1)} 学分',
                            style: TextStyle(
                              fontSize: 9,
                              color: isLearningCreated
                                  ? ink
                                  : ink.withValues(alpha: .6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (text(course, 'teachingClassName').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    text(course, 'teachingClassName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isLearningCreated
                          ? ink
                          : ink.withValues(alpha: .5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterTabs(
    BuildContext context,
    List<SemesterChoice> choices,
  ) {
    if (choices.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final count = choices.length;

        const spacing = 6.0;
        final canFitSingleRow =
            count <= 2 ||
            (availableWidth - (count - 1) * spacing) / count >= 85.0;

        if (canFitSingleRow) {
          return Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(width: spacing),
                Expanded(
                  child: _panelTab(
                    choices[i],
                    isSelected: choices[i].id == selected,
                    availableWidth:
                        (availableWidth - (count - 1) * spacing) / count,
                  ),
                ),
              ],
            ],
          );
        }

        // Otherwise split into at most 2 rows to keep within two lines
        final row1Count = (count + 1) ~/ 2;
        final row1 = choices.sublist(0, row1Count);
        final row2 = choices.sublist(row1Count);

        final widthPerItemRow1 =
            (availableWidth - (row1.length - 1) * spacing) / row1.length;
        final widthPerItemRow2 =
            (availableWidth - (row2.length - 1) * spacing) / row2.length;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (var i = 0; i < row1.length; i++) ...[
                  if (i > 0) const SizedBox(width: spacing),
                  Expanded(
                    child: _panelTab(
                      row1[i],
                      isSelected: row1[i].id == selected,
                      availableWidth: widthPerItemRow1,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < row2.length; i++) ...[
                  if (i > 0) const SizedBox(width: spacing),
                  Expanded(
                    child: _panelTab(
                      row2[i],
                      isSelected: row2[i].id == selected,
                      availableWidth: widthPerItemRow2,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _panelTab(
    SemesterChoice choice, {
    required bool isSelected,
    required double availableWidth,
  }) {
    final displayName = choice.id == 'all' ? '全部学期' : choice.name;
    final horizontalPad = availableWidth < 70
        ? 2.0
        : (availableWidth < 90 ? 4.0 : 6.0);
    final fontSize = availableWidth < 70
        ? 10.5
        : (availableWidth < 90 ? 11.0 : 12.0);

    return InkWell(
      onTap: () {
        if (choice.id != selected) {
          onChanged(choice.id);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: horizontalPad),
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
            displayName,
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

  static String _formatCredit(double cr) {
    if (cr <= 0) return '0';
    return cr == cr.roundToDouble()
        ? cr.toInt().toString()
        : cr.toStringAsFixed(1);
  }

  static SemesterGradeStats _computePanelStats({
    required String selected,
    required List<Json> courses,
    required List<Json> allCourses,
    required List<Json> allGrades,
    required Set<String> matchingIds,
  }) {
    if (selected == 'all') {
      if (allGrades.isNotEmpty) {
        final gs = GradeStats.compute(grades: allGrades, currentSemester: '');
        final totalEnrolled = courseCredits(allCourses);
        int gradedCount = 0;
        for (final g in allGrades) {
          final orig = text(g, 'original', text(g, 'score')).trim();
          if (orig.isNotEmpty && !['弃修', '缓考', '待录'].contains(orig)) {
            gradedCount++;
          }
        }
        return SemesterGradeStats(
          selected: selected,
          gpa: gs.gpa,
          earnedCredits: gs.totalCredits,
          enrolledCredits: totalEnrolled > 0 ? totalEnrolled : gs.totalCredits,
          avgScore: gs.avgScore,
          hasGrades: gs.hasGrades && gs.gpa > 0,
          totalCourses: allCourses.length,
          gradedCourses: gradedCount > 0
              ? gradedCount
              : allCourses.where((c) => text(c, 'score').isNotEmpty).length,
        );
      }
    }

    final normZdbkSem = semesterToId(selected) ?? selected;

    final semGrades = allGrades.where((g) {
      final sem = text(g, 'semester').trim();
      final xkkh = text(g, 'xkkh').trim();
      final semFromXkkh =
          RegExp(r'(\d{4}-\d{4}-[12])').firstMatch(xkkh)?[1] ?? sem;
      return matchingIds.contains(sem) ||
          matchingIds.contains(semFromXkkh) ||
          (normZdbkSem.isNotEmpty &&
              (sem == normZdbkSem || semFromXkkh == normZdbkSem));
    }).toList();

    if (semGrades.isNotEmpty) {
      final gs = GradeStats.compute(
        grades: semGrades,
        currentSemester: normZdbkSem,
      );
      final totalEnrolled = courseCredits(courses);
      int gradedCount = 0;
      for (final g in semGrades) {
        final orig = text(g, 'original', text(g, 'score')).trim();
        if (orig.isNotEmpty && !['弃修', '缓考', '待录'].contains(orig)) {
          gradedCount++;
        }
      }
      return SemesterGradeStats(
        selected: selected,
        gpa: gs.gpa,
        earnedCredits: gs.totalCredits,
        enrolledCredits: totalEnrolled > 0 ? totalEnrolled : gs.totalCredits,
        avgScore: gs.avgScore,
        hasGrades: gs.hasGrades && gs.gpa > 0,
        totalCourses: courses.length,
        gradedCourses: gradedCount,
      );
    }

    double gpaWeighted = 0;
    double gpaCreditSum = 0;
    double scoreWeighted = 0;
    double scoreCreditSum = 0;
    double earnedCreditSum = 0;
    final totalEnrolled = courseCredits(courses);
    int gradedCount = 0;

    for (final c in courses) {
      final cr = double.tryParse('${c['credit']}') ?? 0.0;
      final scoreStr = text(c, 'score', text(c, 'original')).trim();
      final gpaVal = double.tryParse(
        text(c, 'gpa', text(c, 'fivePoint')).trim(),
      );
      final scoreVal = double.tryParse(scoreStr);

      if (scoreStr.isNotEmpty && !['弃修', '缓考', '待录'].contains(scoreStr)) {
        gradedCount++;
        final isFailing =
            scoreStr == '不合格' || (scoreVal != null && scoreVal < 60);
        if (!isFailing && cr > 0) {
          earnedCreditSum += cr;
        }
        if (gpaVal != null &&
            gpaVal >= 0 &&
            cr > 0 &&
            !['合格', '不合格'].contains(scoreStr)) {
          gpaWeighted += gpaVal * cr;
          gpaCreditSum += cr;
        }
        if (scoreVal != null && scoreVal >= 0 && cr > 0) {
          scoreWeighted += scoreVal * cr;
          scoreCreditSum += cr;
        }
      }
    }

    final finalGpa = gpaCreditSum > 0 ? (gpaWeighted / gpaCreditSum) : 0.0;
    final finalAvg = scoreCreditSum > 0
        ? (scoreWeighted / scoreCreditSum)
        : 0.0;

    return SemesterGradeStats(
      selected: selected,
      gpa: finalGpa,
      earnedCredits: earnedCreditSum,
      enrolledCredits: totalEnrolled,
      avgScore: finalAvg,
      hasGrades: gpaCreditSum > 0,
      totalCourses: courses.length,
      gradedCourses: gradedCount,
    );
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

class SemesterGradeStats {
  final String selected;
  final double gpa;
  final double earnedCredits;
  final double enrolledCredits;
  final double avgScore;
  final bool hasGrades;
  final int totalCourses;
  final int gradedCourses;

  const SemesterGradeStats({
    required this.selected,
    required this.gpa,
    required this.earnedCredits,
    required this.enrolledCredits,
    required this.avgScore,
    required this.hasGrades,
    required this.totalCourses,
    required this.gradedCourses,
  });
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
              if (!_isLearningCreated) ...[
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is AppError ? e.message : '操作失败，请重试。')),
        );
      }
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
    if (result.type != ResultType.done) {
      throw AppError('FILE_OPEN_FAILED', result.message);
    }
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
    if (kind == 'image') {
      return Center(
        child: InteractiveViewer(child: Image.file(file, fit: BoxFit.contain)),
      );
    }
    if (kind == 'text') {
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
    }
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

class SubSemesterChoice {
  const SubSemesterChoice({required this.id, required this.name});
  final String id;
  final String name;
}

List<SubSemesterChoice> getSubSemesterChoices(
  String semester, [
  Iterable<TimetableEntry> entries = const [],
]) {
  final s = semester.toLowerCase();
  if (s.contains('秋冬') ||
      s.endsWith('-1') ||
      s.contains('秋') ||
      s.contains('冬')) {
    return const [
      SubSemesterChoice(id: '秋', name: '秋学期'),
      SubSemesterChoice(id: '冬', name: '冬学期'),
    ];
  }
  if (s.contains('春夏') ||
      s.endsWith('-2') ||
      s.contains('春') ||
      s.contains('夏')) {
    return const [
      SubSemesterChoice(id: '春', name: '春学期'),
      SubSemesterChoice(id: '夏', name: '夏学期'),
    ];
  }
  if (s.contains('暑') || s.contains('短') || s.endsWith('-3')) {
    return const [SubSemesterChoice(id: '暑', name: '暑学期')];
  }
  final subs = entries
      .map((e) => e.subSemester.trim())
      .where((sub) => sub.isNotEmpty)
      .toSet();
  if (subs.isNotEmpty) {
    return [for (final sub in subs) SubSemesterChoice(id: sub, name: '$sub学期')];
  }
  return const [];
}

List<TimetableEntry> filterTimetableBySubSemester(
  List<TimetableEntry> entries,
  String subSemester,
) {
  if (subSemester.isEmpty) {
    return entries;
  }
  return entries.where((e) {
    if (e.subSemester.isEmpty) return true;
    return e.subSemester.contains(subSemester);
  }).toList();
}

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
    final choices = getSubSemesterChoices(widget.semester, widget.entries);
    _selectedSubSemester = choices.isNotEmpty ? choices.first.id : '';
  }

  @override
  void didUpdateWidget(TimetableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.semester != widget.semester) {
      final choices = getSubSemesterChoices(widget.semester, widget.entries);
      _selectedSubSemester = choices.isNotEmpty ? choices.first.id : '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final subChoices = getSubSemesterChoices(widget.semester, widget.entries);
    final effectiveSub = subChoices.any((c) => c.id == _selectedSubSemester)
        ? _selectedSubSemester
        : (subChoices.isNotEmpty ? subChoices.first.id : '');
    final filtered = filterTimetableBySubSemester(widget.entries, effectiveSub);
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
          if (widget.entries.isEmpty)
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
      final compactActions = constraints.maxWidth < 620;
      final tabAreaWidth = compactActions
          ? math.max(120.0, constraints.maxWidth - 120)
          : constraints.maxWidth * 0.5;

      final count = widget.choices.length;
      final spacing = count > 4 ? 4.0 : 6.0;
      final estimatedNaturalWidth =
          count * 95.0 + math.max(0, count - 1) * spacing;
      final needAdaptive =
          !compactActions && (estimatedNaturalWidth > tabAreaWidth);

      Widget tabsWidget;
      if (compactActions) {
        tabsWidget = SizedBox(
          width: tabAreaWidth,
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
        tabsWidget = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: tabAreaWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _semesterTab(widget.choices[i], compact: false),
              ],
            ],
          ),
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          tabsWidget,
          const Spacer(),
          Row(
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
                  onPressed: widget.entries.isEmpty
                      ? null
                      : widget.onExportXlsx,
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
                  onPressed: widget.entries.isEmpty
                      ? null
                      : widget.onExportXlsx,
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
          ),
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
      for (final day in _dayNames)
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

double _parseNum(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

class GradeStats {
  final double gpa;
  final double totalCredits;
  final double avgScore;
  final double semesterCredits;
  final bool hasGrades;

  const GradeStats({
    required this.gpa,
    required this.totalCredits,
    required this.avgScore,
    required this.semesterCredits,
    required this.hasGrades,
  });

  bool get hasData => hasGrades;
  double get totalEarnedCredits => totalCredits;
  double get averageScore => avgScore;

  static GradeStats compute({
    required List<Json> grades,
    required String currentSemester,
    List<String> currentCourseNames = const [],
    double timetableCredits = 0.0,
  }) {
    if (grades.isEmpty) {
      return GradeStats(
        gpa: 0,
        totalCredits: 0,
        avgScore: 0,
        semesterCredits: timetableCredits,
        hasGrades: false,
      );
    }

    double gpaWeightedSum = 0;
    double gpaCreditSum = 0;
    double earnedCreditSum = 0;
    double scoreWeightedSum = 0;
    double scoreCreditSum = 0;
    double semCreditSum = 0;

    for (final g in grades) {
      final credit = _parseNum(g['credit']);
      final fivePoint = _parseNum(g['fivePoint']);
      final original = text(g, 'original');
      final included = g['creditIncluded'] == true;
      final gpaIncluded = g['gpaIncluded'] == true;
      final id = text(g, 'id');
      final sem = text(g, 'semester');
      final xkkh = text(g, 'xkkh');
      final semFromXkkh =
          RegExp(
            r'(\d{4}-\d{4}-[12])',
          ).firstMatch(xkkh.isNotEmpty ? xkkh : id)?[1] ??
          '';

      // Check if passed for earned credits
      final scoreVal = double.tryParse(original);
      final isFailing =
          original == '不合格' || (scoreVal != null && scoreVal < 60);
      if (included && !isFailing && credit > 0) {
        earnedCreditSum += credit;
      }

      // GPA calculation
      if (gpaIncluded && credit > 0 && fivePoint >= 0) {
        gpaWeightedSum += fivePoint * credit;
        gpaCreditSum += credit;
      }

      // Average score calculation (from numerical scores)
      if (gpaIncluded && credit > 0 && scoreVal != null && scoreVal >= 0) {
        scoreWeightedSum += scoreVal * credit;
        scoreCreditSum += credit;
      }

      // Semester credit calculation
      final isCurrentSem =
          currentSemester.isNotEmpty &&
          (sem == currentSemester ||
              semFromXkkh == currentSemester ||
              id.contains(currentSemester) ||
              xkkh.contains(currentSemester));
      if (isCurrentSem && credit > 0) {
        semCreditSum += credit;
      }
    }

    // If timetableCredits > 0 (authoritative enrolled / timetable course credits),
    // always prioritize it over partial or early grades in the current ongoing semester.
    if (timetableCredits > 0) {
      semCreditSum = timetableCredits;
    }

    // If semester credits not found directly in currentSemester grades, try matching by course names
    if (semCreditSum == 0 && currentCourseNames.isNotEmpty) {
      final courseCreditMap = <String, double>{};
      for (final g in grades) {
        final name = text(g, 'courseName').trim();
        final cr = _parseNum(g['credit']);
        if (name.isNotEmpty && cr > 0) {
          courseCreditMap[name] = cr;
          courseCreditMap[name
                  .replaceAll(RegExp(r'[（\(].*?[）\)]'), '')
                  .trim()] =
              cr;
        }
      }
      final matched = <String>{};
      for (final rawName in currentCourseNames) {
        final name = rawName.trim();
        final clean = name.replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
        if (matched.contains(name) ||
            (clean.isNotEmpty && matched.contains(clean))) {
          continue;
        }
        if (courseCreditMap.containsKey(name)) {
          semCreditSum += courseCreditMap[name]!;
          matched.add(name);
        } else if (clean.isNotEmpty && courseCreditMap.containsKey(clean)) {
          semCreditSum += courseCreditMap[clean]!;
          matched.add(clean);
        }
      }
    }

    final finalGpa = gpaCreditSum > 0 ? (gpaWeightedSum / gpaCreditSum) : 0.0;
    final finalAvgScore = scoreCreditSum > 0
        ? (scoreWeightedSum / scoreCreditSum)
        : 0.0;

    return GradeStats(
      gpa: finalGpa,
      totalCredits: earnedCreditSum,
      avgScore: finalAvgScore,
      semesterCredits: semCreditSum,
      hasGrades: true,
    );
  }
}

class MultiMetricItem {
  final String value;
  final String label;
  final Color? valueColor;
  final VoidCallback? onTap;
  final String? tooltip;

  const MultiMetricItem({
    required this.value,
    required this.label,
    this.valueColor,
    this.onTap,
    this.tooltip,
  });
}

class MultiMetricKpi extends StatefulWidget {
  const MultiMetricKpi({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    this.foot,
    this.footOnTap,
  });

  final String label;
  final String icon;
  final List<MultiMetricItem> items;
  final String? foot;
  final VoidCallback? footOnTap;

  @override
  State<MultiMetricKpi> createState() => _MultiMetricKpiState();
}

class _MultiMetricKpiState extends State<MultiMetricKpi> {
  int? hoveredIndex;
  bool footHovered = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paperCard,
        border: Border.all(color: ink.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(3),
      ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SvgPicture.asset(
                'assets/icons/${widget.icon}.svg',
                width: 17,
                height: 17,
                colorFilter: ColorFilter.mode(
                  blue.withValues(alpha: .85),
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              for (var i = 0; i < widget.items.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 38,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: ink.withValues(alpha: .08),
                  ),
                Expanded(child: _buildMetricItem(widget.items[i], i)),
              ],
            ],
          ),
          const Spacer(),
          if (widget.foot != null && widget.foot!.isNotEmpty) ...[
            Divider(height: 16, color: ink.withValues(alpha: .1)),
            InkWell(
              onTap: widget.footOnTap,
              onHover: (v) {
                if (mounted) setState(() => footHovered = v);
              },
              borderRadius: BorderRadius.circular(2),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.foot!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: gold,
                          decoration: (widget.footOnTap != null && footHovered)
                              ? TextDecoration.underline
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    if (widget.footOnTap != null)
                      Text(
                        '→',
                        style: TextStyle(
                          fontSize: 16,
                          color: footHovered ? gold : blue,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricItem(MultiMetricItem item, int index) {
    final canTap = item.onTap != null;
    final isHovered = hoveredIndex == index;

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      decoration: BoxDecoration(
        color: isHovered && canTap
            ? blue.withValues(alpha: .06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 28,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  item.value,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: item.valueColor ?? blue,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: isHovered && canTap ? blue : ink,
                fontWeight: isHovered && canTap
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );

    if (!canTap) {
      return item.tooltip != null
          ? Tooltip(message: item.tooltip!, child: content)
          : content;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => hoveredIndex = index);
      },
      onExit: (_) {
        if (mounted) setState(() => hoveredIndex = null);
      },
      child: Tooltip(
        message: item.tooltip ?? '',
        waitDuration: const Duration(milliseconds: 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(4),
            child: content,
          ),
        ),
      ),
    );
  }
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
                  SizedBox(
                    height: 44,
                    child: Row(
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
                                fontSize: widget.small ? 28 : 36,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                        if (widget.unit.isNotEmpty)
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 5,
                              ),
                              child: Text(
                                widget.unit,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: ink,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.foot.isNotEmpty) ...[
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
    this.trailing,
  });
  final String title;
  final String? icon;
  final Widget? trailing;
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
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
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
    this.titleSuffix,
    this.subtitle,
    this.updatedAt,
    this.trailing,
  });
  final String title;
  final Widget? titleSuffix;
  final String? subtitle, updatedAt;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            if (titleSuffix != null) ...[
              const SizedBox(width: 12),
              Flexible(child: titleSuffix!),
            ],
          ],
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: ink),
            ),
          ),
        if (updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              updatedAt!,
              style: TextStyle(fontSize: 11, color: ink.withValues(alpha: .58)),
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
                ?trailing,
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

List<SemesterChoice> semesterChoices(List<Json> raw, {bool includeAll = true}) {
  final map = <String, SemesterChoice>{};
  for (final s in raw) {
    final name = text(s, 'name'), id = semesterToId(name) ?? text(s, 'id');
    if (id.isEmpty) continue;
    final yearMatch = RegExp(
      r'(\d{4}-\d{4})',
    ).firstMatch(name.isNotEmpty ? name : id);
    final year = yearMatch != null
        ? yearMatch.group(1)!
        : (id.length >= 9 ? id.substring(0, 9) : id);
    final tabName = id.endsWith('-1')
        ? '$year秋冬'
        : id.endsWith('-2')
        ? '$year春夏'
        : semesterDisplay(id, name);
    map[id] = SemesterChoice(id, tabName);
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
  if (includeAll) {
    result.add(const SemesterChoice('all', '全部学期（所有历史课程）'));
  }
  return result;
}

String semesterDisplay(String id, String name) {
  final yearMatch = RegExp(
    r'(\d{4}-\d{4})',
  ).firstMatch(name.isNotEmpty ? name : id);
  final year = yearMatch != null
      ? yearMatch.group(1)!
      : (id.length >= 9 ? id.substring(0, 9) : id);

  if (name.contains('秋冬')) return '$year秋冬';
  if (name.contains('春夏')) return '$year春夏';
  if (name.contains('秋')) return '$year秋';
  if (name.contains('冬')) return '$year冬';
  if (name.contains('春')) return '$year春';
  if (name.contains('夏')) return '$year夏';
  if (name.contains('短')) return '$year短';

  final normalized = semesterToId(name) ?? id;
  if (normalized.endsWith('-1')) return '$year秋冬';
  if (normalized.endsWith('-2')) return '$year春夏';
  return name.isEmpty ? normalized : name;
}

String cleanCourseExtraSuffix(String n) {
  var s = n.trim();
  s = s.replaceAll('(', '（').replaceAll(')', '）');
  String prev;
  do {
    prev = s;
    // 仅去除末尾的学期标识，例如（2024-2025-1）、（2024-2025秋冬）、（2024-2025学年秋学期）
    s = s.replaceAll(RegExp(r'（\d{4}-\d{4}[^）]*）$'), '').trim();
    // 仅去除末尾的选课代码/教学班，例如（061B0170-01）、（CS101-01）、（教学班01）、（01班）
    s = s
        .replaceAll(
          RegExp(r'（(?:[A-Za-z0-9_]+-[A-Za-z0-9_]+|教学班\d+|\d+班)）$'),
          '',
        )
        .trim();
  } while (s != prev);
  return s;
}

String normalizeCourseName(String n) {
  var s = cleanCourseExtraSuffix(n);

  // 统一括号为（）并去除多余空白
  s = s
      .replaceAll('(', '（')
      .replaceAll(')', '）')
      .replaceAll(RegExp(r'\s+'), '');

  // 1系列精确对齐为（1），绝不混淆
  s = s.replaceAll(RegExp(r'（(?:1|一|Ⅰ|I)）'), '（1）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅰ|I|1|一)$'),
    '（1）',
  );

  // 2系列精确对齐为（2），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:2|二|Ⅱ|II)[）\)]'), '（2）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅱ|II|2|二)$'),
    '（2）',
  );

  // 3系列精确对齐为（3），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:3|三|Ⅲ|III)[）\)]'), '（3）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅲ|III|3|三)$'),
    '（3）',
  );

  // 4系列精确对齐为（4），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:4|四|Ⅳ|IV)[）\)]'), '（4）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅳ|IV|4|四)$'),
    '（4）',
  );

  // 5系列精确对齐为（5），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:5|五|Ⅴ|V)[）\)]'), '（5）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅴ|V|5|五)$'),
    '（5）',
  );

  s = s.replaceAll(RegExp(r'\s+'), '');
  return s;
}

String cleanCourseBaseName(String n) => normalizeCourseName(n);

String formatGradeBadge(String score, String gpa) {
  final s = score.trim();
  final g = double.tryParse(gpa.trim());
  final isNumScore = double.tryParse(s) != null;
  final scoreDisplay = isNumScore ? '$s分' : s;

  if (scoreDisplay.isNotEmpty && g != null && g >= 0) {
    return '$scoreDisplay / $gpa';
  } else if (scoreDisplay.isNotEmpty) {
    return scoreDisplay;
  } else if (g != null && g >= 0) {
    return '绩点 $gpa';
  }
  return '';
}

Future<Json> loadCourseOverview(
  AppServices s,
  String semester, {
  bool refresh = false,
  List<Json>? semestersOverride,
  List<Json>? rawCoursesOverride,
  List<TimetableEntry>? timetableOverride,
}) async {
  final semesters =
      semestersOverride ?? await s.campus.semesters(refresh: refresh);
  final rawCourses =
      rawCoursesOverride ?? await s.campus.courses(refresh: refresh);

  List<Json> allGrades = [];
  try {
    allGrades = await s.campus.grades('', refresh: refresh);
  } catch (_) {}
  if (allGrades.isEmpty) {
    try {
      final cached = await s.db.get('cache', 'grades:');
      if (cached != null) allGrades = rows(cached['items']);
    } catch (_) {}
  }

  List<Json> allEnrolled = [];
  try {
    allEnrolled = await s.campus.enrolledCourses('all', refresh: refresh);
  } catch (_) {}
  if (allEnrolled.isEmpty) {
    try {
      final cached = await s.db.get('cache', 'enrolled_courses:all');
      if (cached != null) allEnrolled = rows(cached['items']);
    } catch (_) {}
  }
  if (allEnrolled.isEmpty) {
    try {
      allEnrolled = await s.campus.enrolledCourses(semester, refresh: refresh);
    } catch (_) {}
  }

  List<TimetableEntry> ttEntries = timetableOverride ?? [];
  if (timetableOverride == null) {
    try {
      ttEntries = await s.campus.timetable(semester, refresh: refresh);
    } catch (_) {}
  }
  if (ttEntries.isEmpty) {
    try {
      final cached = await s.db.get('cache', 'timetable:$semester');
      if (cached != null) {
        ttEntries = rows(cached['items']).map(TimetableEntry.fromJson).toList();
      }
    } catch (_) {}
  }

  final semesterIdToZdbkCode = <String, String>{};
  for (final raw in rows(semesters)) {
    final rawId = text(raw, 'id').trim();
    final sName = text(raw, 'name').trim();
    final zdbkCode = semesterToId(sName) ?? semesterToId(rawId);
    if (rawId.isNotEmpty && zdbkCode != null) {
      semesterIdToZdbkCode[rawId] = zdbkCode;
    }
  }

  // Authoritative course list from 教务网 (ZDBK)
  final zdbkCoursesMap = <String, Map<String, dynamic>>{};
  void addOrUpdateZdbkCourse({
    required String name,
    required String semester,
    double credit = 0.0,
    String teacher = '',
    String xkkh = '',
    String location = '',
    String scheduleTime = '',
    String score = '',
    String gpa = '',
  }) {
    final rawName = cleanCourseExtraSuffix(name);
    if (rawName.isEmpty) return;
    final normName = normalizeCourseName(rawName);
    final normSem = semesterToId(semester) ?? semester;
    final key = '$normSem|$normName';

    if (!zdbkCoursesMap.containsKey(key)) {
      zdbkCoursesMap[key] = {
        'name': rawName,
        'semesterId': normSem,
        'semester': normSem,
        'credit': credit,
        'teacher': teacher,
        'xkkh': xkkh,
        'location': location,
        'scheduleTime': scheduleTime,
        if (score.isNotEmpty) 'score': score,
        if (score.isNotEmpty) 'original': score,
        if (gpa.isNotEmpty) 'gpa': gpa,
        if (gpa.isNotEmpty) 'fivePoint': gpa,
      };
    } else {
      final existing = zdbkCoursesMap[key]!;
      if ((existing['credit'] as num? ?? 0) <= 0 && credit > 0) {
        existing['credit'] = credit;
      }
      if (text(existing, 'teacher').isEmpty && teacher.isNotEmpty) {
        existing['teacher'] = teacher;
      }
      if (text(existing, 'xkkh').isEmpty && xkkh.isNotEmpty) {
        existing['xkkh'] = xkkh;
      }
      if (text(existing, 'location').isEmpty && location.isNotEmpty) {
        existing['location'] = location;
      }
      if (text(existing, 'scheduleTime').isEmpty && scheduleTime.isNotEmpty) {
        existing['scheduleTime'] = scheduleTime;
      }
      if (score.isNotEmpty) {
        existing['score'] = score;
        existing['original'] = score;
      }
      if (gpa.isNotEmpty) {
        existing['gpa'] = gpa;
        existing['fivePoint'] = gpa;
      }
    }
  }

  // 1. Ingest enrolled courses from ZDBK (考签/已选课程)
  for (final e in allEnrolled) {
    final n = text(e, 'courseName', text(e, 'name')).trim();
    final sem = text(e, 'semester').trim();
    final cr = double.tryParse('${e['credit']}') ?? 0.0;
    final teacher = text(e, 'teacher').trim();
    final xkkh = text(e, 'xkkh').trim();
    final loc = text(e, 'location').trim();
    addOrUpdateZdbkCourse(
      name: n,
      semester: sem.isNotEmpty ? sem : semester,
      credit: cr,
      teacher: teacher,
      xkkh: xkkh,
      location: loc,
    );
  }

  // 2. Ingest timetable entries from ZDBK (教务网课表)
  for (final e in ttEntries) {
    final sem = e.semester.trim().isNotEmpty ? e.semester.trim() : semester;
    final weekText = e.weeks.isNotEmpty ? '${compressWeeks(e.weeks)} 周' : '';
    final subText = e.subSemester.isNotEmpty ? '${e.subSemester} ' : '';
    final timeStr =
        '周${_weekdayName(e.weekday)} ${e.startSection}-${e.endSection}节 ($subText$weekText)';
    addOrUpdateZdbkCourse(
      name: e.courseName,
      semester: sem,
      credit: e.credit,
      teacher: e.teacher,
      xkkh: e.id,
      location: e.location,
      scheduleTime: timeStr,
    );
  }

  // 3. Ingest cached timetables from DB
  try {
    final cachedTtIds = await s.db.ids('cache', prefix: 'timetable:');
    for (final cid in cachedTtIds) {
      final cItem = await s.db.get('cache', cid);
      final semFromCid = cid.replaceFirst('timetable:', '').trim();
      if (cItem != null && cItem['items'] is List) {
        for (final row in rows(cItem['items'])) {
          final tName = text(row, 'courseName').trim();
          final tTeacher = text(row, 'teacher').trim();
          final tCredit = double.tryParse('${row['credit']}') ?? 0.0;
          final tXkkh = text(row, 'classCode', text(row, 'xkkh')).trim();
          final tLoc = text(row, 'location', text(row, 'room')).trim();
          final tSem = semFromCid.isNotEmpty ? semFromCid : semester;
          if (tName.isNotEmpty) {
            addOrUpdateZdbkCourse(
              name: tName,
              semester: tSem,
              credit: tCredit,
              teacher: tTeacher,
              xkkh: tXkkh,
              location: tLoc,
            );
          }
        }
      }
    }
  } catch (_) {}

  // 4. Ingest historical grades from ZDBK (全量成绩库)
  for (final g in allGrades) {
    final n = text(g, 'courseName').trim();
    final sem = text(g, 'semester').trim();
    final cr = double.tryParse('${g['credit']}') ?? 0.0;
    final teacher = text(g, 'teacher').trim();
    final original = text(g, 'original', text(g, 'score')).trim();
    final fivePoint = text(
      g,
      'fivePoint',
      text(g, 'gpa', text(g, 'jd')),
    ).trim();
    final xkkh = text(g, 'classCode', text(g, 'xkkh')).trim();
    addOrUpdateZdbkCourse(
      name: n,
      semester: sem,
      credit: cr,
      teacher: teacher,
      xkkh: xkkh,
      score: original,
      gpa: fivePoint,
    );
  }

  // 5. Match each unified 教务网 course with 学在浙大 (rawCourses)
  final courses = <Json>[];
  if (zdbkCoursesMap.isNotEmpty) {
    for (final entry in zdbkCoursesMap.entries) {
      final zItem = entry.value;
      final zName = text(zItem, 'name');
      final zNorm = normalizeCourseName(zName);
      final zSem = text(zItem, 'semesterId');
      final zXkkh = text(zItem, 'xkkh');

      Json? matchedLearning;

      // 5.1 Match by courseCode from xkkh
      if (zXkkh.isNotEmpty) {
        for (final lc in rawCourses) {
          final cCode = text(lc, 'courseCode').trim();
          if (cCode.isNotEmpty && zXkkh.contains(cCode)) {
            final lcSemId = text(lc, 'semesterId');
            final lcZdbkSem =
                semesterIdToZdbkCode[lcSemId] ?? semesterToId(lcSemId) ?? '';
            if (lcZdbkSem.isEmpty || lcZdbkSem == zSem) {
              matchedLearning = lc;
              break;
            }
          }
        }
      }

      // 5.2 Match by normalized name and semester
      if (matchedLearning == null) {
        for (final lc in rawCourses) {
          final lcName = text(lc, 'name').trim();
          final lcNorm = normalizeCourseName(lcName);
          if (lcNorm == zNorm) {
            final lcSemId = text(lc, 'semesterId');
            final lcZdbkSem =
                semesterIdToZdbkCode[lcSemId] ?? semesterToId(lcSemId) ?? '';
            if (lcZdbkSem == zSem) {
              matchedLearning = lc;
              break;
            }
          }
        }
      }

      // 5.3 Match by normalized name if only 1 candidate exists
      if (matchedLearning == null) {
        final candidates = rawCourses.where((lc) {
          return normalizeCourseName(text(lc, 'name').trim()) == zNorm;
        }).toList();
        if (candidates.length == 1) {
          matchedLearning = candidates.first;
        }
      }

      final isCreated =
          matchedLearning != null && text(matchedLearning, 'id').isNotEmpty;
      courses.add({
        ...zItem,
        'id': isCreated ? text(matchedLearning, 'id') : '',
        'learningZjuCreated': isCreated,
        if (isCreated && text(matchedLearning, 'teachingClassName').isNotEmpty)
          'teachingClassName': text(matchedLearning, 'teachingClassName'),
        if (text(zItem, 'teacher').isEmpty &&
            isCreated &&
            text(matchedLearning, 'teacher').isNotEmpty)
          'teacher': text(matchedLearning, 'teacher'),
      });
    }
  } else {
    // Fallback if no ZDBK course data is found at all (e.g. offline unit tests)
    for (final c in rawCourses) {
      courses.add({...c, 'learningZjuCreated': text(c, 'id').isNotEmpty});
    }
  }

  // 6. Merge semesters so tabs cover all historical semesters in 教务网
  final existingSemIds = <String>{
    for (final s in rows(semesters)) text(s, 'id'),
    for (final s in rows(semesters))
      if (semesterToId(text(s, 'name')) != null) semesterToId(text(s, 'name'))!,
  };
  final mergedSemesters = [...rows(semesters)];
  for (final c in courses) {
    final sId = text(c, 'semesterId', text(c, 'semester')).trim();
    if (sId.isNotEmpty && !existingSemIds.contains(sId)) {
      existingSemIds.add(sId);
      final yearMatch = RegExp(r'(\d{4}-\d{4})').firstMatch(sId);
      final year = yearMatch != null ? yearMatch.group(1)! : sId;
      final semLabel = sId.endsWith('-1')
          ? '$year学年秋冬学期'
          : (sId.endsWith('-2') ? '$year学年春夏学期' : sId);
      mergedSemesters.add({
        'id': sId,
        'name': semLabel,
        'isActive': sId == semester,
      });
    }
  }

  final time = await s.campus.oldestUpdatedAt(
    cacheKeys: [
      'semesters',
      'courses',
      'grades:',
      'enrolled_courses:all',
      'timetable:$semester',
    ],
  );

  return {
    'semesters': mergedSemesters,
    'courses': courses,
    'grades': allGrades,
    if (time != null) '_updatedAt': time.toIso8601String(),
  };
}

int? deadlineMs(Json a) {
  final raw = text(a, 'deadline');
  final date = DateTime.tryParse(raw);
  return date?.millisecondsSinceEpoch;
}

const oneWeekMs = 7 * 24 * 3600 * 1000;

bool isVisibleAssignment(Json a, int nowMs) {
  final due = deadlineMs(a);
  if (due == null) return true;
  if (due > nowMs) return true;
  return nowMs - due <= oneWeekMs;
}

int? examMs(Json a) {
  final date = DateTime.tryParse(text(a, 'time'));
  return date?.millisecondsSinceEpoch;
}

bool isSubmitted(Json a) => a['submitted'] == true;

int compareAssignments(Json a, Json b) {
  final subA = isSubmitted(a), subB = isSubmitted(b);
  if (subA != subB) return subA ? 1 : -1;
  final da = deadlineMs(a), db = deadlineMs(b);
  if (da == null && db == null) return 0;
  if (da == null) return 1;
  if (db == null) return -1;
  return da.compareTo(db);
}

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
  if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(ext)) {
    return 'image';
  }
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
