import 'package:flutter/material.dart';

import '../../application/page_loaders/courses_loader.dart';
import '../../domain/course_catalog.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../courses/course_actions.dart';
import '../courses/course_overview_state.dart';
import '../courses/timetable_view.dart';
import '../export.dart';
import '../shared/campus_page.dart';
import '../shared/file_actions.dart';
import '../theme.dart';

class CoursesPage extends CampusDataPage {
  const CoursesPage({super.key, required super.services});
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends CampusPageState<CoursesPage>
    with
        FileActions<CoursesPage>,
        CourseOverviewState<CoursesPage>,
        CourseActions<CoursesPage> {
  @override
  String get pageKey => '/courses';
  @override
  String get title => '课程表';

  @override
  String semester = academicSemester(beijing(DateTime.now()));
  final exportKey = GlobalKey();
  bool _exporting = false;
  @override
  bool get preloadOverview => true;
  @override
  bool get showRefreshButton => false;
  @override
  Future<Json> load({bool refresh = false}) =>
      loadCoursesPage(s, semester, refresh: refresh);
  @override
  bool usesCache(String key) =>
      key == 'semesters' || key.startsWith('timetable:');
  @override
  PageContext buildPageContext({Json? activeCourse, String? courseTab}) =>
      PageContext.courses(
        timetableSemester: semester,
        overviewSemester: overviewSemester,
        activeCourse: activeCourse,
        courseTab: courseTab,
      );
  @override
  VoidCallback? get openSidePanel => openRightPanel;
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

  /// 学期总览辅助栏是否已收起。收起后只在右缘保留一条窄栏用于重新展开，
  /// 把横向空间让给课程表网格。
  bool overviewCollapsed = false;

  @override
  Widget sidePanel(double width) => overviewCollapsed
      ? _collapsedOverviewRail()
      : SizedBox(
          width: width >= 1200 ? 288 : 260,
          child: Container(
            decoration: BoxDecoration(
              color: paperCard.withValues(alpha: .62),
              border: Border(
                left: BorderSide(color: ink.withValues(alpha: .15)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 100),
            child: RefreshIndicator(
              color: blue,
              backgroundColor: paperCard,
              onRefresh: refreshOverview,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: overviewPanelContent(
                  onCollapse: () => setState(() => overviewCollapsed = true),
                ),
              ),
            ),
          ),
        );

  /// 收起状态下的窄栏：只保留展开按钮。
  Widget _collapsedOverviewRail() => SizedBox(
    width: 44,
    child: Container(
      decoration: BoxDecoration(
        color: paperCard.withValues(alpha: .62),
        border: Border(left: BorderSide(color: ink.withValues(alpha: .15))),
      ),
      child: Column(
        children: [
          const SizedBox(height: 26),
          IconButton(
            tooltip: '展开学期总览',
            onPressed: () => setState(() => overviewCollapsed = false),
            icon: const Icon(Icons.chevron_left, size: 20, color: ink),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
  );
  Future<void> openRightPanel() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: paperCard,
    builder: (ctx) => ListenableBuilder(
      listenable: overviewChanges,
      builder: (ctx, _) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .82,
        child: RefreshIndicator(
          color: blue,
          backgroundColor: paperCard,
          onRefresh: refreshOverview,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: overviewPanelContent(),
          ),
        ),
      ),
    ),
  );
  @override
  List<Widget> content(Json d, {required bool wide}) {
    final choices = semesterChoices(
      rows(d['semesters'] ?? []),
      includeAll: false,
    );
    if (choices.isNotEmpty && semester == 'all') semester = choices.first.id;
    final entries = rows(d['timetable']).map(TimetableEntry.fromJson).toList();
    return [
      RepaintBoundary(
        key: exportKey,
        child: TimetableView(
          entries: entries,
          semester: semester,
          wide: wide,
          choices: choices,
          refreshing: refreshing,
          isExporting: _exporting,
          onSemesterChanged: (id) {
            setState(() {
              semester = id;
            });
            syncPageContext();
            refresh(force: false);
          },
          onExportPng: () => act(_exportTimetablePng),
          onExportXlsx: () => act(() => exportXlsx(entries, semester)),
          onRefresh: refresh,
          onSelectCourse: openTimetableCourse,
        ),
      ),
    ];
  }
}
