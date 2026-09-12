import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/course_overview.dart';
import '../../domain/course_catalog.dart';
import '../../domain/models.dart';
import '../shared/campus_page.dart';
import '../theme.dart';
import 'course_right_panel.dart';

mixin CourseOverviewState<T extends CampusDataPage> on CampusPageState<T> {
  String get semester;
  bool get preloadOverview => false;
  Future<Json>? overviewData;
  String overviewSemester = 'all';
  bool _refreshingOverview = false;
  bool _loadingOverviewData = false;
  Timer? _overviewReloadTimer;
  StreamSubscription<String>? _overviewSubscription;
  // Modal routes do not rebuild when the page behind them calls setState.
  final overviewChanges = ValueNotifier<int>(0);

  void _notifyOverviewChanged() {
    if (mounted) overviewChanges.value++;
  }

  @override
  void initState() {
    super.initState();
    _overviewSubscription = s.campus.cacheChanges.listen((key) {
      if (mounted &&
          !_loadingOverviewData &&
          overviewData != null &&
          _overviewUsesCache(key)) {
        _scheduleOverviewReload();
      }
    });
    if (preloadOverview) {
      overviewData = loadOverview(
        refresh: s.claimInitialRefresh('/courses:panel'),
      );
    }
  }

  @override
  void dispose() {
    _overviewSubscription?.cancel();
    _overviewReloadTimer?.cancel();
    overviewChanges.dispose();
    super.dispose();
  }

  Future<void> courseDetail(Json course);
  Future<Json> _loadOverviewData({bool refresh = false}) async {
    _loadingOverviewData = true;
    try {
      return await loadCourseOverview(s, semester, refresh: refresh);
    } finally {
      _loadingOverviewData = false;
    }
  }

  bool _overviewUsesCache(String key) {
    return key == 'semesters' ||
        key == 'courses' ||
        key == 'grades:' ||
        key == 'enrolled_courses:all' ||
        key.startsWith('timetable:');
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
    if (mounted) {
      setState(() {
        overviewData = next;
      });
      _notifyOverviewChanged();
    }
    try {
      await next;
    } catch (_) {
      if (mounted && identical(overviewData, next)) {
        setState(() {
          overviewData = previous;
        });
        _notifyOverviewChanged();
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
      _notifyOverviewChanged();
    }
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the page error; refresh controls should settle.
    } finally {
      if (mounted) {
        setState(() => _refreshingOverview = false);
        _notifyOverviewChanged();
      } else {
        _refreshingOverview = false;
      }
    }
  }

  Future<Json> loadOverview({bool refresh = false}) =>
      _loadOverviewData(refresh: refresh);
  Widget overviewPanelContent({VoidCallback? onCollapse}) =>
      FutureBuilder<Json>(
        future: overviewData ??= loadOverview(
          refresh: s.claimInitialRefresh('/courses:panel'),
        ),
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
                      onPressed: refreshOverview,
                      child: const Text('重试', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) return const SizedBox.shrink();
          final d = snapshot.data!;
          return CourseRightPanel(
            data: d,
            selected: overviewSemester,
            refreshing: _refreshingOverview,
            onChanged: (value) {
              setState(() => overviewSemester = value);
              syncPageContext();
              _notifyOverviewChanged();
            },
            onRefresh: refreshOverview,
            onSelect: courseDetail,
            onCollapse: onCollapse,
          );
        },
      );
  Future<void> openCourseOverviewSheet({String? initialSemester}) {
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
      builder: (ctx) => ListenableBuilder(
        listenable: overviewChanges,
        builder: (ctx, _) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .85,
          child: RefreshIndicator(
            color: blue,
            backgroundColor: paperCard,
            onRefresh: refreshOverview,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              // 右侧多留出滚动条宽度：桌面端 Scrollbar 画在滚动视图右缘，
              // 内容不内缩就会被压住。
              padding: const EdgeInsets.fromLTRB(20, 18, 34, 28),
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
                              onPressed: refreshOverview,
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
                      syncPageContext();
                      _notifyOverviewChanged();
                    },
                    onRefresh: refreshOverview,
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
}
