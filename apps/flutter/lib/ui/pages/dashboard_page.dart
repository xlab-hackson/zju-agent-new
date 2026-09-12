import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../application/page_loaders/dashboard_loader.dart';
import '../../domain/assignment_rules.dart';
import '../../domain/course_catalog.dart';
import '../../domain/formatters.dart';
import '../../domain/grade_stats.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../assignments/assignment_card.dart';
import '../courses/course_actions.dart';
import '../courses/course_overview_state.dart';
import '../dashboard/connection_card.dart';
import '../dashboard/dashboard_header.dart';
import '../dashboard/dashboard_schedule.dart';
import '../dashboard/kpi.dart';
import '../dashboard/multi_metric_kpi.dart';
import '../dashboard/tool_card.dart';
import '../shared/campus_page.dart';
import '../shared/external_links.dart';
import '../shared/file_actions.dart';
import '../shared/page_empty.dart';
import '../shared/page_header.dart';
import '../theme.dart';

class DashboardPage extends CampusDataPage {
  const DashboardPage({super.key, required super.services});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends CampusPageState<DashboardPage>
    with
        FileActions<DashboardPage>,
        CourseOverviewState<DashboardPage>,
        CourseActions<DashboardPage> {
  @override
  String get pageKey => '/';
  @override
  String get title => '工作台';

  @override
  String semester = academicSemester(beijing(DateTime.now()));
  String upcomingTab = 'schedule';
  int urgentHours = 24;
  @override
  bool get needsSecondTicker => true;
  @override
  Future<Json> load({bool refresh = false}) =>
      loadDashboardPage(s, semester, refresh: refresh);
  @override
  bool usesCache(String key) =>
      key == 'semesters' ||
      key == 'courses' ||
      key == 'grades:' ||
      key == 'enrolled_courses:all' ||
      key.startsWith('calendar:') ||
      key.startsWith('timetable:') ||
      key.startsWith('exams:') ||
      key.startsWith('assignments:');
  @override
  PageContext buildPageContext({Json? activeCourse, String? courseTab}) =>
      PageContext.dashboard();
  @override
  List<Widget> content(Json data, {required bool wide}) => const [];
  @override
  Widget buildPageContent(AsyncSnapshot<Json> snapshot, {required bool wide}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _dashboard(snapshot),
      );
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
    // 隐藏绩点只作用于本卡的绩点与均分；辅助栏、课程表与课程列表仍正常显示。
    final hideGpa = settings['hideGpa'] == true;
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
      DashboardHeader(
        name: name,
        info: dateInfo,
        campusStatus: campusStatus,
        avatarDataUrl: avatarDataUrl,
        updatedLabel: dataUpdatedLabel(text(d, '_updatedAt')),
        onRefresh: refresh,
      ),
      if (d['_hasStaleData'] == true)
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            '部分数据未能刷新，当前仍包含上次成功获取的数据。',
            style: TextStyle(fontSize: 12, color: gold),
          ),
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
        DashboardSchedule(
          events: events,
          info: dateInfo,
          now: now,
          onSelectCourse: openEventCourse,
        )
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
        hideGpa: hideGpa,
      ),
      ChapterHead(juan: '卷三', title: '校园百宝箱', icon: 'scroll'),
      _toolGrid(),
      ChapterHead(juan: '卷四', title: '系统与连接', icon: 'key'),
      _connectionGrid(d),
    ];
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
    required bool hideGpa,
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
                    openCourseOverviewSheet();
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
                  value: hideGpa
                      ? '*'
                      : gradeStats.hasData && gradeStats.gpa > 0
                      ? gradeStats.gpa.toStringAsFixed(2)
                      : '--',
                  label: '目前总绩点',
                  tooltip: '五分制加权绩点 (GPA)，点击查看学业总览',
                  onTap: () {
                    overviewSemester = 'all';
                    openCourseOverviewSheet(initialSemester: 'all');
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
                    openCourseOverviewSheet(initialSemester: 'all');
                  },
                ),
                MultiMetricItem(
                  value: hideGpa
                      ? '*'
                      : gradeStats.hasData && gradeStats.averageScore > 0
                      ? gradeStats.averageScore.toStringAsFixed(1)
                      : '--',
                  label: '百分制均分',
                  tooltip: '百分制加权平均分，点击查看学业总览',
                  onTap: () {
                    overviewSemester = 'all';
                    openCourseOverviewSheet(initialSemester: 'all');
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
  Widget _assignmentCard(Json a) => AssignmentCard(
    assignment: a,
    now: now,
    urgentHours: urgentHours,
    onTap: () => assignmentDetail(a),
  );
}
