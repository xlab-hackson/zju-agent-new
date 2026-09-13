# Flutter 页面与业务模块

`feature_page.dart` 是轻量路由适配器。每个页面拥有独立的 State，路由变化会切换页面 Widget；无需再向一个公共 State 添加分支或筛选字段。

| 页面 | 入口 |
| --- | --- |
| 工作台 | `dashboard_page.dart` |
| 课程表 | `courses_page.dart` |
| 待办作业 | `assignments_page.dart` |
| 考试安排 | `exams_page.dart` |
| 学校信息 | `school_info_page.dart` |
| 下载中心 | `downloads_page.dart` |
| 智云课堂占位页 | `classroom_page.dart` |

公共职责按以下边界维护：

- `ui/shared/campus_page.dart`：页面布局、加载/错误状态、刷新、缓存通知订阅与释放。页面通过 `load`、`usesCache`、`buildPageContext` 等接口声明自身行为；这里不按路由判断业务。
- `ui/courses/course_overview_state.dart`：工作台和课程页共用的辅助栏状态、独立刷新和弹层。`overviewChanges` 通知已打开的弹层更新数据 Future、学期和刷新状态，弹层通过 `ListenableBuilder` 订阅；通知器随页面释放。`course_actions.dart` 管理课程详情弹层及页面上下文同步。
- `ui/shared/file_actions.dart`：下载/预览动作和反馈，供课程与作业页面复用。
- `ui/courses/`、`ui/assignments/`、`ui/exams/`、`ui/downloads/`、`ui/dashboard/`：各功能的卡片、课表、详情弹层等组件。跨功能通用组件在 `ui/shared/`。
- `application/page_loaders/`：各页的数据请求和缓存更新时间聚合。工作台继续共享 `upcoming()` 的结果，下载页只读本地记录。
- `application/course_overview.dart`：首页和辅助栏唯一的课程总览聚合入口 `loadCourseOverview`。
- `application/course_details.dart`：课程查找及课表元信息补全，不接收 `BuildContext`。
- `domain/course_catalog.dart`、`grade_stats.dart`、`assignment_rules.dart`、`timetable_options.dart`、`formatters.dart`：课程/学期匹配、学业统计、截止时间规则、小学期筛选和格式化；不依赖 Flutter UI。

新增页面应独立维护筛选条件和页面上下文，只声明自己使用的缓存 key。首次进入通过稳定的 `pageKey` 领取本次运行的一次强制刷新；用户主动刷新强制联网，缓存变更通知只触发普通缓存重组。课程表与辅助栏分别订阅和刷新。

刷新结束时必须在页面仍挂载的情况下同步更新状态，使按钮退出刷新中状态。更新数据 Future 时使用同步语句块，不能让 `setState` 的赋值表达式返回 Future。更新时间只取实际依赖缓存中最早的成功时间；工作台的 `_hasStaleData` 提示部分资源刷新失败，保留其上次成功时间。

应用入口和测试直接引用实际模块，不保留集中兼容导出文件。业务模块不应反向依赖 UI。

验证使用 `flutter analyze` 和 `flutter test`。`test/feature_page_lifecycle_test.dart` 覆盖路由切换、筛选状态隔离、一次性刷新、缓存通知、本地下载页及 1320/800/390px 宽度下的页面渲染。最近验证范围与后续未验证改动见 [Flutter README](../../../README.md)。
