# Celechron 日程逻辑借鉴与重构说明文档

> 本文档详细记录 `zju-agent` 在日程、课表与校历时间系统设计中，对开源项目 **Celechron** 的借鉴内容、改动原因以及我们的独立重构设计。

---

## 一、 为什么重构现有的学期与日程逻辑？

在重构之前，`zju-agent` 存在如下核心问题：
1. **对「学在浙大」接口的严重脆弱依赖**：
   - 之前系统判断“当前学期”主要依靠 `courses.getSemesters()`，并检查返回的 `is_active` 字段。
   - **痛点**：学在浙大后台的 `is_active` 状态更新滞后，在学期交替、假期、开学前夕经常出现无活跃学期或停留在旧学期的情况；此外，查课表和考试本来是教务网（ZDBK）的职责，每次查教务课表却要前置发起一个学在浙大的网络请求，链路冗余且脆弱。
2. **缺乏真实公历时间映射与调休感知**：
   - 正方教务系统返回的课表只是抽象规则（“星期二第 3-4 节，1-8 周”）；
   - 当学生问 Agent *“我明天有什么课”*、*“今天下午要不要上课”* 时，系统无法感知当天是公历几月几号、第几周、是否放假、是否因为国庆/中秋调休而需要上另一天的课。

---

## 二、 借鉴 Celechron 的核心设计

从 Celechron（Flutter 客户端，源码位于 `/home/yt/zjuagent/Celechron`）中，我们借鉴了以下设计思路与算法模型：

### 1. 权威校历配置文件机制（`CalendarConfig`）
- **Celechron 来源**：[`time_config_service.dart`](file:///home/yt/zjuagent/Celechron/lib/http/time_config_service.dart) 及 `calendar.celechron.top/${semesterId}.json`。
- **借鉴内容**：
  - **时段划分（`startEnd`）**：采用 `[前半段开始, 前半段结束, 后半段开始, 后半段结束]` 的 8 位日期数组（如 `["20240909", "20241103", "20241104", "20241229"]`），清晰界定秋/冬（或春/夏）两阶段及考试周；
  - **法定节假日（`holiday`）**：`{ "YYYYMMDD": "节日名" }`，标记停课放假日；
  - **调休对换映射（`exchange`）**：采用 16 位成对编码 `"{原放假日YYYYMMDD}{补课调休公历日YYYYMMDD}": "节日名"`（例如 `"2024100420240929": "国庆节"` 表示 9 月 29 日按 10 月 4 日（周五）课表补课）；
  - **非教学放假（`dummy`）**：标记周末休假等辅助信息。

### 2. 浙大作息时刻表标准化（`sessionTime`）
- **Celechron 来源**：`calendar.celechron.top` 中的 `sessionTime` 数组。
- **借鉴内容**：
  - 浙大标准 1~15 节课的标准起止时间映射（第 1 节 08:00–08:45，第 2 节 08:50–09:35，...，第 15 节 22:10–22:55）。

### 3. 日程动态展开与排他/位移算法
- **Celechron 来源**：[`semester.dart:147-297`](file:///home/yt/zjuagent/Celechron/lib/model/semester.dart#L147-L297) 的 `periods` 计算属性。
- **借鉴内容**：
  - **周次与星期映射**：从学期第一周周一作为基准原点，通过 `(week - 1) * 7 + (weekday - 1)` 计算出每一次课程在公历上的精确日期；
  - **节假日剔除**：若计算出的公历日期在 `holiday` 中，则直接剔除该节课；
  - **调休映射（Effective Weekday）**：如果当天是 `exchange` 中的补课日，将对应原假期的星期几课程平移到当天执行。

### 4. 统一日程事件模型（`Period / ScheduleEvent`）
- **Celechron 来源**：[`period.dart`](file:///home/yt/zjuagent/Celechron/lib/model/period.dart)。
- **借鉴内容**：
  - 将常规周期性课程（`class`）、单次期中期末考试（`exam`）、作业截止任务（`assignment`）统一融合成标准的日程单元，包含统一的时间轴字段（`startTime`, `endTime`, `title`, `location` 等）。

### 5. 「接下来」页面流式交互与倒计时机制（`FlowView / FlowController`）
- **Celechron 来源**：[`flow_view.dart`](file:///home/yt/zjuagent/Celechron/lib/page/flow/flow_view.dart) 及 [`flow_controller.dart`](file:///home/yt/zjuagent/Celechron/lib/page/flow/flow_controller.dart)。
- **借鉴内容**：
  - **首项聚焦（Hero Card）**：将未来 48 小时内的第一项日程作为首要焦点，明确区分“正在进行”（`ongoing`）与“即将开始”（`upcoming`）；
  - **秒级实时倒计时**：前端驱动时钟逐秒递减，展示“离结束还有 HH:MM:SS”或“距开始还有 HH:MM:SS”；
  - **动态进度条**：对正在进行中的课程/考试计算 `(now - start) / (end - start)` 时间消耗百分比，展示平滑进度条；
  - **随后的安排（Later Periods）**：结构化展示 48 小时内的后续课程或考试条目，带友好相对时间（如“2小时后”、“明天08:00”）；
  - **48 小时截止作业模块**：聚合即将到期的作业，默认折叠，展开时直观呈现各科 DDL 紧迫度。

---

## 三、 本项目的独立重构与增强

在本项目中，我们**未照搬 Dart 源码**，而是结合 `zju-agent` 的 TypeScript 技术栈与 Agent 业务场景进行了全新实现和升级：

| 维度 | Celechron 原始实现 | `zju-agent` 重构设计 |
| :--- | :--- | :--- |
| **开发语言与架构** | Dart / Flutter GetX 响应式 | 现代 TypeScript，符合 monorepo 分层架构（`core` 纯类型、`zju-services` 服务适配、`server` 调度与工具） |
| **学期判断源** | 前端按学号推算循环请求所有学期 | **彻底摒弃「学在浙大」判断学期**，改由 `CalendarService` 基于权威校历与真实时钟推算当前学年学期，0 网络成本且 100% 准确 |
| **离线与高可用** | 完全依赖远程 `calendar.celechron.top`，无网络时降级脆弱 | **内置离线校历回退库（Bundled Fallback Calendars）** + SQLite `campus_cache`，离线或断网时依然秒级计算所有日程与周次 |
| **Agent 工具深度集成** | 仅用于移动端 UI 列表渲染 | **全面赋予 Agent 语义级时间感知**：提供 `zju_get_upcoming_schedule`、`zju_get_timetable` 与 `zju_get_daily_schedule`，用户问“接下来有什么课”、“未来48小时安排”、“最近有什么作业快截止了”时，大模型可直接调用并获得高精度日程流 |
| **Dashboard 全面改版** | 传统 Flutter SliverList | Web 端以现代响应式 UI 全面重构 Dashboard：顶部校历坐标轴、48小时 Celechron 风格日程流、默认折叠作业栏、快捷状态栏 |
| **错误容灾与边界处理** | 针对跨越 16 周的非常规课写有 hardcode 分支 | 通过统一的 `AcademicDateInfo` 状态机计算，完整覆盖开学注册周、教学周（秋/冬/春/夏）、考试周、寒暑假的判定 |

---

## 四、 核心接口与模块分布

1. **协议与领域算法层**：[`archive/packages/core/src/domain/schedule.ts`](file:///home/yt/zjuagent/zju-agent/archive/packages/core/src/domain/schedule.ts)
   - 定义 `SemesterCalendarConfig`、`AcademicDateInfo`、`ScheduleEvent`、`UpcomingPeriod`、`UpcomingAssignment`、`UpcomingSchedule48h`；
   - 算法函数 `calculateAcademicDateInfo`、`projectTimetableToDay`、`buildDailySchedule`、`buildUpcomingSchedule48h`。
2. **服务层**：[`archive/packages/zju-services/src/calendar/index.ts`](file:///home/yt/zjuagent/zju-agent/archive/packages/zju-services/src/calendar/index.ts)
   - `CalendarService`：负责校历加载、远程同步、缓存保鲜及日程事件聚合推算；新增 `getUpcomingSchedule48h(...)` 方法。
3. **工具与路由层**：
   - 路由 [`archive/packages/server/src/routes/zdbk.ts`](file:///home/yt/zjuagent/zju-agent/archive/packages/server/src/routes/zdbk.ts)：新增 `GET /api/zju/schedule/upcoming-48h`；
   - 工具 [`archive/packages/server/src/agent/tools.ts`](file:///home/yt/zjuagent/zju-agent/archive/packages/server/src/agent/tools.ts)：新增 `zju_get_upcoming_schedule` 工具；
   - 提示词 [`archive/packages/server/src/agent/loop.ts`](file:///home/yt/zjuagent/zju-agent/archive/packages/server/src/agent/loop.ts)：提示词指引大模型优先选用接下来 48 小时日程流。
4. **Web 前端交互层**：
   - Hook [`archive/apps/web/src/api/zju.ts`](file:///home/yt/zjuagent/zju-agent/archive/apps/web/src/api/zju.ts)：新增 `useUpcomingSchedule48h`；
   - 页面 [`archive/apps/web/src/pages/Dashboard.tsx`](file:///home/yt/zjuagent/zju-agent/archive/apps/web/src/pages/Dashboard.tsx)：改版为 Celechron 接下来 48 小时日程流、Hero 首项卡片、秒级倒计时、默认折叠的 48 小时截止作业栏目。
