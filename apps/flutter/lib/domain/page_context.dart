import 'dart:convert';
import 'models.dart';

/// 针对当前页面推荐调用的校园 API 及建议参数
class PageApiGuide {
  const PageApiGuide({
    required this.api,
    required this.purpose,
    this.suggestedParams = const {},
  });

  final String api;
  final String purpose;
  final Map<String, dynamic> suggestedParams;

  Map<String, dynamic> toJson() => {
    'api': api,
    'purpose': purpose,
    if (suggestedParams.isNotEmpty) 'suggestedParams': suggestedParams,
  };
}

/// 用户当前界面的实时感知上下文，供 Agent 获取并在提示词中指引模型
class PageContext {
  const PageContext({
    required this.route,
    required this.pageTitle,
    required this.contentSummary,
    this.details = const {},
    this.recommendedApis = const [],
  });

  final String route;
  final String pageTitle;
  final String contentSummary;
  final Map<String, dynamic> details;
  final List<PageApiGuide> recommendedApis;

  Map<String, dynamic> toJson() => {
    'route': route,
    'pageTitle': pageTitle,
    'contentSummary': contentSummary,
    'details': details,
    'recommendedApis': recommendedApis.map((a) => a.toJson()).toList(),
  };

  /// 转换为注入到 System Prompt 中的结构化文本描述
  String toPrompt() {
    final buffer = StringBuffer();
    buffer.writeln('【用户当前界面上下文感知】');
    buffer.writeln('用户当前正在客户端中查看以下界面：');
    buffer.writeln('- 当前页面：$pageTitle (路由: $route)');
    if (details.isNotEmpty) {
      buffer.writeln('- 界面与辅助栏状态：');
      for (final entry in details.entries) {
        buffer.writeln('  * ${entry.key}: ${entry.value}');
      }
    }
    if (contentSummary.isNotEmpty) {
      buffer.writeln('- 页面内容概述：');
      buffer.writeln('  $contentSummary');
    }
    if (recommendedApis.isNotEmpty) {
      buffer.writeln('- 针对当前界面的 API / 工具调用推荐：');
      for (final guide in recommendedApis) {
        final paramsDesc = guide.suggestedParams.isNotEmpty
            ? ' (推荐参数: ${jsonEncode(guide.suggestedParams)})'
            : '';
        buffer.writeln('  * ${guide.api}: ${guide.purpose}$paramsDesc');
      }
    }
    buffer.writeln('【重要交互指引】');
    buffer.writeln('1. 当用户使用代词（如“这个课”、“这里的作业”、“今天有什么课”、“课件发我”）提问时，请优先指代上述界面上下文中的课程、学期或内容。');
    buffer.writeln('2. 查找具体内容时，请优先使用上述推荐的 API/工具及其推荐参数，避免盲目猜测。');
    return buffer.toString().trim();
  }

  /// 工作台首页
  factory PageContext.dashboard() => const PageContext(
    route: '/',
    pageTitle: '工作台',
    contentSummary:
        '工作台首页，展示学生个人概览、今日及未来48小时真实日程/待办速览、当前学期课程数/作业数/考试数统计卡片、校园快捷服务入口及校历。',
    details: {'视图类型': '工作台总览'},
    recommendedApis: [
      PageApiGuide(
        api: 'zju_get_upcoming_schedule',
        purpose: '查询未来48小时内的真实课程日程与临近待办作业',
      ),
      PageApiGuide(
        api: 'zju_get_daily_schedule',
        purpose: '按校历查询某天真实日程与上课安排（需传入 date: YYYY-MM-DD）',
      ),
      PageApiGuide(api: 'zju_get_courses', purpose: '查询当前学期所有已选课程列表'),
      PageApiGuide(api: 'zju_get_assignments', purpose: '查询未截止或待办作业'),
      PageApiGuide(api: 'zju_get_exams', purpose: '查询本学期考试安排'),
      PageApiGuide(api: 'zju_get_grades', purpose: '查询历年成绩、均绩与绩点'),
    ],
  );

  /// 课程表页面与右侧辅助栏（学期总览、课程详情抽屉）
  factory PageContext.courses({
    required String timetableSemester,
    required String overviewSemester,
    Json? activeCourse,
    String? courseTab,
  }) {
    final hasActiveCourse = activeCourse != null;
    final courseName = hasActiveCourse ? text(activeCourse, 'name') : '';
    final courseId = hasActiveCourse ? text(activeCourse, 'id') : '';
    final tabName = courseTab == 'assignments' ? '课程作业' : '课件资料';

    final details = <String, dynamic>{
      '课程表当前学期': timetableSemester,
      '辅助栏(学期总览)学期': overviewSemester == 'all' ? '全部学期' : overviewSemester,
      '辅助栏状态': '展示所选学期的课程列表卡片',
    };

    if (hasActiveCourse) {
      details['当前打开的课程详情'] = '$courseName (ID: $courseId)';
      details['课程详情当前Tab'] = tabName;
    }

    final contentSummary = hasActiveCourse
        ? '主视图为当前学期课程表网格；右侧辅助栏为课程列表；当前正展开课程《$courseName》的详情抽屉，正在查看“$tabName”列表。'
        : '主视图展示每周一至周日第1至13节的课程表网格；右侧辅助栏（学期总览）展示选定学期的全部已选课程列表卡片。';

    final recommended = <PageApiGuide>[];

    if (hasActiveCourse) {
      if (courseTab == 'assignments') {
        recommended.add(
          PageApiGuide(
            api: 'zju_get_assignments',
            purpose: '查询当前查看的课程《$courseName》的作业列表与截止时间',
            suggestedParams: {'courseId': courseId},
          ),
        );
        recommended.add(
          PageApiGuide(
            api: 'zju_get_course_materials',
            purpose: '查询《$courseName》的课件资料文件（供写作业参考）',
            suggestedParams: {'courseId': courseId},
          ),
        );
      } else {
        recommended.add(
          PageApiGuide(
            api: 'zju_get_course_materials',
            purpose: '查询当前查看的课程《$courseName》的课件与参考资料列表',
            suggestedParams: {'courseId': courseId},
          ),
        );
        recommended.add(
          PageApiGuide(
            api: 'zju_get_assignments',
            purpose: '查询《$courseName》的课程作业要求',
            suggestedParams: {'courseId': courseId},
          ),
        );
      }
      recommended.add(
        PageApiGuide(
          api: 'zju_get_quizzes',
          purpose: '查询《$courseName》的在线测验安排',
          suggestedParams: {'courseId': courseId},
        ),
      );
      recommended.add(
        PageApiGuide(
          api: 'zju_download_course_material',
          purpose: '下载《$courseName》的课件资料文件到本地',
          suggestedParams: {'courseId': courseId},
        ),
      );
    }

    recommended.addAll([
      PageApiGuide(
        api: 'zju_get_timetable',
        purpose: '查询指定学期课表节次与上课教室',
        suggestedParams: {'semester': timetableSemester},
      ),
      PageApiGuide(
        api: 'zju_get_daily_schedule',
        purpose: '按校历日期查询具体某天的上课安排与节次时间',
      ),
      PageApiGuide(
        api: 'zju_get_courses',
        purpose: '查询辅助栏中选定学期的课程列表',
        suggestedParams: {
          if (overviewSemester != 'all') 'semesterId': overviewSemester,
        },
      ),
    ]);

    return PageContext(
      route: '/courses',
      pageTitle: '课程表',
      contentSummary: contentSummary,
      details: details,
      recommendedApis: recommended,
    );
  }

  /// 待办作业页面
  factory PageContext.assignments({
    String tab = 'all',
    int urgentHours = 24,
  }) {
    final tabLabel = switch (tab) {
      'pending' => '待提交',
      'submitted' => '已提交',
      _ => '全部',
    };

    return PageContext(
      route: '/assignments',
      pageTitle: '待办作业',
      contentSummary:
          '展示各门课程的待办作业列表（按未提交未截止、未提交逾期1周内、已提交排序），过滤展示未截止及截止未超过1周的作业。',
      details: {'当前筛选Tab': tabLabel, '紧急作业阈值': '$urgentHours小时'},
      recommendedApis: const [
        PageApiGuide(
          api: 'zju_get_assignments',
          purpose: '查询所有课程作业或指定课程作业列表、截止时间与提交状态',
        ),
        PageApiGuide(
          api: 'zju_get_course_materials',
          purpose: '查询作业所属课程的课件资料文件（参考资料）',
        ),
        PageApiGuide(api: 'zju_get_courses', purpose: '查询作业所属的课程基本信息'),
      ],
    );
  }

  /// 考试安排页面
  factory PageContext.exams({required String semester}) => PageContext(
    route: '/exams',
    pageTitle: '考试安排',
    contentSummary: '展示指定学期的期末/期中考试科目、考试具体时间、考场地点、座位号及考核方式（统考/院系考）。',
    details: {'当前考试学期': semester},
    recommendedApis: [
      PageApiGuide(
        api: 'zju_get_exams',
        purpose: '查询考试科目、考场地点与座位安排',
        suggestedParams: {'semester': semester},
      ),
    ],
  );

  /// 学校信息 / 通知公告页面
  factory PageContext.schoolInfo({String source = 'all'}) {
    final sourceLabel = switch (source) {
      'bksy' => '本科生院(教务处)',
      'sutuo' => '素质拓展网',
      _ => '全部来源',
    };
    return PageContext(
      route: '/school-info',
      pageTitle: '学校信息',
      contentSummary: '浙江大学公开通知公告，汇集本科生院教务通知（选课、调课、教学安排等）与素质拓展网讲座活动竞赛通知。',
      details: {'当前通知来源': sourceLabel},
      recommendedApis: [
        PageApiGuide(
          api: 'zju_get_notices',
          purpose: '查询教务处或素拓网的最新通知与公告详情',
          suggestedParams: {'source': source},
        ),
      ],
    );
  }

  /// 本地下载管理页面
  factory PageContext.downloads() => const PageContext(
    route: '/downloads',
    pageTitle: '下载管理',
    contentSummary: '管理本地已下载的课程资料与课件文件，支持直接调用系统应用打开、按课程筛选、重新下载或删除。',
    details: {'存储介质': '本地磁盘 downloads 目录'},
    recommendedApis: [
      PageApiGuide(
        api: 'zju_get_course_materials',
        purpose: '在线查询学在浙大课程可供下载的课件列表',
      ),
      PageApiGuide(
        api: 'zju_download_course_material',
        purpose: '下载课程课件文件到本地 downloads 目录',
      ),
    ],
  );

  /// 系统设置页面
  factory PageContext.settings() => const PageContext(
    route: '/settings',
    pageTitle: '设置',
    contentSummary:
        '本地应用设置，包含大模型 API 来源管理（检测可用性）、统一身份认证账号绑定、个性化设置（头像、昵称、人设提示词）、本地下载目录及数据备份导出。',
    details: {'配置范围': '客户端本地偏好与模型服务'},
    recommendedApis: [],
  );

  /// 智云课堂外链页面
  factory PageContext.classroom() => const PageContext(
    route: '/classroom',
    pageTitle: '智云课堂',
    contentSummary: '浙大智云课堂等外部校园教学服务导航与快捷跳转入口。',
    details: {'服务形式': '外部浏览器跳转'},
    recommendedApis: [
      PageApiGuide(api: 'zju_get_courses', purpose: '查询我的课程名称以在智云课堂中搜索回放'),
    ],
  );

  /// 首次配置向导页面
  factory PageContext.setup() => const PageContext(
    route: '/setup',
    pageTitle: '首次配置向导',
    contentSummary: '引导初次使用用户绑定浙大统一身份认证账号并配置大模型 API 来源。',
    details: {'向导阶段': '初始初始化'},
    recommendedApis: [],
  );
}
