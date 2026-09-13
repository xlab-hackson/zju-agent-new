import 'dart:async';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../application/services.dart';
import '../domain/models.dart';

const _widgetPanel = Color(0x990f172a);
const _widgetWhite = Color(0xffffffff);
const _widgetGreen = Color(0xff34d399);
const _widgetRose = Color(0xfffb7185);
const _widgetWeekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

class DesktopHost with TrayListener, WindowListener {
  DesktopHost(this.services, this.window, {this.onOpenPath});
  final AppServices services;
  final WindowController window;
  final void Function(String path)? onOpenPath;
  WindowController? widget;
  static Future<DesktopHost> initialize(
    AppServices services, {
    void Function(String path)? onOpenPath,
  }) async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1320, 900),
        minimumSize: Size(800, 600),
        title: '求是助手',
      ),
      () async {
        await windowManager.show();
      },
    );
    final host = DesktopHost(
      services,
      await WindowController.fromCurrentEngine(),
      onOpenPath: onOpenPath,
    );
    // 热重载/热重启只会重建主窗口的 Dart 状态，desktop_multi_window
    // 已创建的子窗口可能仍然存在。复用已有挂件并隐藏其余实例，确保
    // 小球和展开面板始终属于同一个挂件窗口。
    final existingWidgets = (await WindowController.getAll())
        .where(
          (candidate) =>
              candidate.windowId != host.window.windowId &&
              candidate.arguments.startsWith('widget:'),
        )
        .toList();
    if (existingWidgets.isNotEmpty) {
      host.widget = existingWidgets.first;
      for (final duplicate in existingWidgets.skip(1)) {
        await duplicate.hide();
      }
    }
    await host.window.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'schedule':
          return services.campus.upcoming();
        case 'ask':
          final question = call.arguments as String;
          var answer = '';
          await for (final event in services.agent.chat(
            question,
            widget: true,
          )) {
            if (event.type == 'text') answer += text(event.data, 'delta');
            if (event.type == 'error') answer = text(event.data, 'message');
          }
          return answer;
        case 'open':
          final path = call.arguments is String
              ? call.arguments as String
              : null;
          await windowManager.show();
          await windowManager.focus();
          if (path != null) onOpenPath?.call(path);
          return true;
        default:
          throw const AppError('INVALID_INPUT', '未知窗口消息。');
      }
    });
    final icon = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'tray.ico',
    );
    await trayManager.setIcon(icon);
    // tray_manager 0.5.3 的 Windows 实现在首次 NIM_ADD 时会把尚未初始化的
    // nid.szTip（垃圾内存）备份后原样写回，并因此设置 NIF_TIP，导致鼠标悬停
    // 托盘图标时显示乱码。这里显式设置 tooltip 覆盖掉那个值。
    // 必须在 setIcon 之后调用：SetToolTip 走 NIM_MODIFY，要求图标已经存在。
    await trayManager.setToolTip('求是助手');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: '打开主界面'),
          MenuItem(key: 'widget', label: '显示 / 隐藏挂件'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
    trayManager.addListener(host);
    windowManager.addListener(host);
    await windowManager.setPreventClose(true);
    return host;
  }

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'open') {
      await windowManager.show();
      await windowManager.focus();
    }
    if (menuItem.key == 'widget') {
      if (widget == null) {
        widget = await WindowController.create(
          WindowConfiguration(
            arguments: 'widget:${window.windowId}',
            hiddenAtLaunch: true,
          ),
        );
        await widget!.show();
      } else {
        await widget!.invokeMethod<void>('toggle');
      }
    }
    if (menuItem.key == 'exit') {
      services.agent.cancelAll();
      await services.db.close();
      await trayManager.destroy();
      exit(0);
    }
  }
}

Future<void> prepareWidget() async {
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(380, 560),
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.show();
    },
  );
}

class WidgetApp extends StatefulWidget {
  const WidgetApp({super.key, required this.mainWindow});
  final String mainWindow;
  @override
  State<WidgetApp> createState() => _WidgetAppState();
}

class _WidgetAppState extends State<WidgetApp> {
  static const expandedSize = Size(380, 560), collapsedSize = Size(64, 64);
  final input = TextEditingController();
  Timer? timer;
  Timer? ticker;
  List<Json> events = [];
  Json dateInfo = {};
  String updatedAt = '', answer = '', question = '', error = '';
  bool asking = false, loaded = false, collapsed = false;
  late final host = WindowController.fromWindowId(widget.mainWindow);
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    WindowController.fromCurrentEngine().then(
      (c) => c.setWindowMethodHandler((call) async {
        if (call.method == 'toggle') {
          if (await windowManager.isVisible()) {
            await windowManager.hide();
          } else {
            await windowManager.show();
          }
        }
      }),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    ticker?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final data = object(await host.invokeMethod<dynamic>('schedule'));
      if (mounted) {
        setState(() {
          events = rows(data['events']);
          dateInfo = object(data['dateInfo'] ?? {});
          updatedAt = text(data, 'now');
          error = '';
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loaded = true;
          error = '日程暂不可用，请在主界面检查账号与网络。';
        });
      }
    }
  }

  Future<void> ask() async {
    final prompt = input.text.trim();
    if (asking || prompt.isEmpty) return;
    // 发送后立即清空输入框：主聊天窗（ui/chat.dart 的 send）同样如此，
    // 挂件这里此前漏掉了，导致消息发出后文字仍停留在输入框里。
    input.clear();
    setState(() {
      asking = true;
      question = prompt;
      answer = '';
    });
    try {
      final value = await host.invokeMethod<String>('ask', prompt);
      if (mounted) setState(() => answer = value ?? '');
    } catch (_) {
      if (mounted) setState(() => answer = '问答未完成，请重试。');
    } finally {
      if (mounted) setState(() => asking = false);
    }
  }

  DateTime? eventTime(Json event, String key) {
    final date = text(event, 'date'), time = text(event, key);
    if (date.isEmpty || time.isEmpty) return null;
    return DateTime.tryParse('${date}T$time:00');
  }

  Future<void> toggleCollapsed() async {
    final bounds = await windowManager.getBounds();
    final center = Offset(
      bounds.left + bounds.width / 2,
      bounds.top + bounds.height / 2,
    );
    final size = collapsed ? expandedSize : collapsedSize;
    final position = Offset(
      center.dx - size.width / 2,
      center.dy - size.height / 2,
    );
    await windowManager.setBounds(null, position: position, size: size);
    if (mounted) setState(() => collapsed = !collapsed);
  }

  DateTime eventEnd(Json event, DateTime start) {
    final end = eventTime(event, 'endTime');
    if (end != null && end.isAfter(start)) return end;
    return start.add(Duration(hours: text(event, 'type') == 'exam' ? 2 : 1));
  }

  String friendlyDate(String date, DateTime now) {
    final target = DateTime.tryParse(date);
    if (target == null) return date;
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(target.year, target.month, target.day);
    final delta = day.difference(today).inDays;
    if (delta == 0) return '今天';
    if (delta == 1) return '明天';
    if (delta == 2) return '后天';
    return '${target.month}月${target.day}日';
  }

  String clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String formatHms(int seconds) {
    final total = seconds < 0 ? 0 : seconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final rest = total % 60;
    final pad = (int value) => value.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:${pad(minutes)}:${pad(rest)}' : '${pad(minutes)}:${pad(rest)}';
  }

  String formatDurationChinese(int seconds) {
    if (seconds <= 0) return '0秒';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final rest = seconds % 60;
    if (hours > 0) return '${hours}小时${minutes}分';
    if (minutes > 0) return '${minutes}分${rest}秒';
    return '${rest}秒';
  }

  String sectionLabel(Json event) {
    final start = integer(event['startSection']);
    final end = integer(event['endSection'], start);
    return start > 0 ? '第$start-${end}节' : '';
  }

  Widget header() {
    final week = text(dateInfo, 'weekString');
    final weekday = integer(dateInfo['weekday']);
    final title = week.isEmpty
        ? '浙大校园助手'
        : '$week · ${weekday >= 1 && weekday <= 7 ? _widgetWeekdays[weekday - 1] : ''}';
    final semester = text(dateInfo, 'semesterId');
    final year = semester.length >= 9 ? semester.substring(0, 9) : '';
    final term = semester.endsWith('-1') ? '秋冬' : '春夏';
    final subtitle = year.isEmpty ? '浙大校园助手' : '$year 学年 $term · $week';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _widgetWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _widgetWhite.withAlpha(140), fontSize: 10),
                  ),
                ],
              ),
            ),
            IconButton(
      onPressed: () => toggleCollapsed(),
              tooltip: '隐藏挂件（可从托盘图标重新显示）',
              icon: const Icon(Icons.close_rounded),
              color: _widgetWhite.withAlpha(120),
              iconSize: 15,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget sectionTitle(IconData icon, String title, [int? count]) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 12, color: _widgetWhite.withAlpha(115)),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: _widgetWhite.withAlpha(115),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: .5,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(color: _widgetWhite.withAlpha(75), fontSize: 10)),
        ],
      ],
    ),
  );

  Widget centerHint({required String message, IconData? icon, bool spin = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spin)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_widgetWhite.withAlpha(90)),
                  ),
                )
              else
                Icon(icon ?? Icons.calendar_today_outlined, size: 20, color: _widgetWhite.withAlpha(90)),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: _widgetWhite.withAlpha(130), fontSize: 11),
              ),
            ],
          ),
        ),
      );

  Widget ongoingCard(Json event, DateTime now, DateTime start, DateTime end) {
    final duration = end.difference(start).inMilliseconds;
    final progress = duration <= 0
        ? 0.0
        : (now.difference(start).inMilliseconds / duration).clamp(0.0, 1.0).toDouble();
    final title = text(event, 'title', '未命名日程');
    final section = sectionLabel(event);
    final teacher = text(event, 'teacher');
    final location = text(event, 'location', '未安排教室');
    final detail = '${section.isEmpty ? '' : '$section · '}${text(event, 'startTime')} - ${text(event, 'endTime')} · $location${teacher.isEmpty ? '' : ' · $teacher'}';

    return InkWell(
      onTap: () => host.invokeMethod<void>('open', '/'),
      borderRadius: BorderRadius.circular(12),
      hoverColor: _widgetGreen.withAlpha(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _widgetGreen.withAlpha(38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _widgetGreen.withAlpha(64)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: _widgetGreen, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text(
                '正在进行',
                style: TextStyle(color: _widgetGreen, fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _widgetWhite, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _widgetWhite.withAlpha(155), fontSize: 10),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('距离下课', style: TextStyle(color: _widgetWhite.withAlpha(140), fontSize: 10)),
              Text(
                formatHms(end.difference(now).inSeconds),
                style: const TextStyle(
                  color: _widgetGreen,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: _widgetWhite.withAlpha(38),
                valueColor: const AlwaysStoppedAnimation(_widgetGreen),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget periodRow(Json event, DateTime now) {
    final start = eventTime(event, 'startTime');
    final title = text(event, 'type') == 'exam' && !text(event, 'title').startsWith('[考试]')
        ? '[考试] ${text(event, 'title', '未命名日程')}'
        : text(event, 'title', '未命名日程');
    final section = sectionLabel(event);
    final location = text(event, 'location', '未安排教室');
    return InkWell(
      onTap: () => host.invokeMethod<void>('open', '/'),
      borderRadius: BorderRadius.circular(8),
      hoverColor: _widgetWhite.withAlpha(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _widgetWhite, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  friendlyDate(text(event, 'date'), now),
                  style: TextStyle(color: _widgetWhite.withAlpha(130), fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  '${section.isEmpty ? '' : '$section '}${text(event, 'startTime')}-${text(event, 'endTime')}',
                  style: TextStyle(color: _widgetWhite.withAlpha(140), fontSize: 10, fontFamily: 'monospace'),
                ),
                const SizedBox(width: 8),
                Icon(Icons.location_on_outlined, size: 11, color: _widgetWhite.withAlpha(90)),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _widgetWhite.withAlpha(140), fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget assignmentRow(Json event, DateTime now) {
    final due = DateTime.tryParse(text(event, 'deadline'))?.toLocal() ??
        eventTime(event, 'startTime') ?? now;
    final remaining = due.difference(now).inSeconds;
    final urgent = remaining > 0 && remaining < 24 * 3600;
    return InkWell(
      onTap: () => host.invokeMethod<void>('open'),
      borderRadius: BorderRadius.circular(8),
      hoverColor: _widgetWhite.withAlpha(26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    text(event, 'title', '未命名作业'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _widgetWhite, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
                if (remaining > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (urgent ? _widgetRose : _widgetWhite).withAlpha(38),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      formatDurationChinese(remaining),
                      style: TextStyle(
                        color: urgent ? _widgetRose : _widgetWhite.withAlpha(155),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    text(event, 'courseName'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _widgetWhite.withAlpha(130), fontSize: 10),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${friendlyDate(text(event, 'date'), now)} ${clock(due)} 截止',
                  style: TextStyle(color: _widgetWhite.withAlpha(130), fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget errorCard() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _widgetRose.withAlpha(38),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _widgetRose.withAlpha(64)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '暂时无法获取日程',
          style: TextStyle(color: Color(0xffffe4e6), fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(error, style: TextStyle(color: _widgetWhite.withAlpha(155), fontSize: 10, height: 1.4)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => host.invokeMethod<void>('open'),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _widgetWhite.withAlpha(26), borderRadius: BorderRadius.circular(6)),
            child: Text('检查账号设置', style: TextStyle(color: _widgetWhite.withAlpha(205), fontSize: 10)),
          ),
        ),
      ],
    ),
  );

  Widget connectedBody() {
    final now = DateTime.now();
    final periods = events.where((event) => text(event, 'type') != 'assignment').toList();
    Json? ongoing;
    DateTime? ongoingStart;
    DateTime? ongoingEnd;
    for (final event in periods) {
      final start = eventTime(event, 'startTime');
      if (start == null) continue;
      final end = eventEnd(event, start);
      if (!now.isBefore(start) && now.isBefore(end)) {
        ongoing = event;
        ongoingStart = start;
        ongoingEnd = end;
        break;
      }
    }
    final next = periods.where((event) {
      final start = eventTime(event, 'startTime');
      return start != null && start.isAfter(now);
    }).take(5).toList();
    final assignments = events.where((event) => text(event, 'type') == 'assignment').take(4).toList();
    final empty = ongoing == null && next.isEmpty && assignments.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: [
        if (ongoing != null && ongoingStart != null && ongoingEnd != null)
          ongoingCard(ongoing, now, ongoingStart, ongoingEnd),
        if (ongoing != null && (next.isNotEmpty || assignments.isNotEmpty)) const SizedBox(height: 10),
        if (next.isNotEmpty) ...[
          sectionTitle(Icons.calendar_today_outlined, '接下来'),
          for (var i = 0; i < next.length; i++) ...[
            periodRow(next[i], now),
            if (i < next.length - 1) const SizedBox(height: 2),
          ],
        ],
        if (next.isNotEmpty && assignments.isNotEmpty) const SizedBox(height: 10),
        if (assignments.isNotEmpty) ...[
          sectionTitle(Icons.checklist_outlined, '待办作业', assignments.length),
          for (var i = 0; i < assignments.length; i++) ...[
            assignmentRow(assignments[i], now),
            if (i < assignments.length - 1) const SizedBox(height: 2),
          ],
        ],
        if (empty) centerHint(message: '48 小时内没有安排'),
      ],
    );
  }

  Widget chat() {
    final hasAnswer = question.isNotEmpty || answer.isNotEmpty || asking;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _widgetWhite.withAlpha(26)))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasAnswer)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _widgetWhite.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _widgetWhite.withAlpha(26)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          question,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _widgetWhite.withAlpha(115), fontSize: 10),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          question = '';
                          answer = '';
                        }),
                        tooltip: '清空回答',
                        icon: const Icon(Icons.close_rounded),
                        iconSize: 13,
                        color: _widgetWhite.withAlpha(90),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (answer.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: SingleChildScrollView(
                          child: Text(
                            answer,
                            style: const TextStyle(color: _widgetWhite, fontSize: 11, height: 1.4),
                          ),
                        ),
                      ),
                    )
                  else if (asking)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation(_widgetWhite.withAlpha(120)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('思考中…', style: TextStyle(color: _widgetWhite.withAlpha(115), fontSize: 10)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  enabled: !asking,
                  maxLength: 200,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => ask(),
                  style: const TextStyle(color: _widgetWhite, fontSize: 11),
                  cursorColor: _widgetWhite,
                  decoration: InputDecoration(
                    hintText: '问一句（只读 · 简短回答）',
                    hintStyle: TextStyle(color: _widgetWhite.withAlpha(90), fontSize: 11),
                    filled: true,
                    fillColor: _widgetWhite.withAlpha(26),
                    isDense: true,
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _widgetWhite.withAlpha(64)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: input,
                builder: (context, value, _) {
                  final disabled = asking || value.text.trim().isEmpty;
                  return SizedBox(
                    width: 29,
                    height: 29,
                    child: Material(
                      color: _widgetWhite.withAlpha(disabled ? 13 : 38),
                      borderRadius: BorderRadius.circular(8),
                      child: IconButton(
                        onPressed: disabled ? null : () => ask(),
                        tooltip: '发送',
                        padding: EdgeInsets.zero,
                        iconSize: 13,
                        color: _widgetWhite.withAlpha(disabled ? 70 : 205),
                        icon: asking
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  valueColor: AlwaysStoppedAnimation(_widgetWhite),
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget footer() {
    final parsed = DateTime.tryParse(updatedAt)?.toLocal();
    final updated = parsed == null ? '—' : clock(parsed);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _widgetWhite.withAlpha(26)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('更新 $updated', style: TextStyle(color: _widgetWhite.withAlpha(100), fontSize: 10)),
          InkWell(
            onTap: () => host.invokeMethod<void>('open', '/'),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('打开应用', style: TextStyle(color: _widgetWhite.withAlpha(155), fontSize: 10)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new_rounded, size: 11, color: _widgetWhite.withAlpha(155)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget collapsedBall() {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggleCollapsed,
        onPanStart: (_) => windowManager.startDragging(),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _widgetPanel,
            shape: BoxShape.circle,
            border: Border.all(color: _widgetWhite.withAlpha(45)),
          ),
          child: const Text(
            '求是',
            style: TextStyle(
              color: _widgetWhite,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = !loaded
        ? centerHint(message: '正在同步日程…', spin: true)
        : error.isNotEmpty && events.isEmpty
        ? errorCard()
        : connectedBody();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'NotoSerifSC',
        scaffoldBackgroundColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        colorScheme: const ColorScheme.dark(primary: _widgetWhite),
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: collapsed
            ? collapsedBall()
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: _widgetPanel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _widgetWhite.withAlpha(26)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      header(),
                      Expanded(child: body),
                      chat(),
                      footer(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
