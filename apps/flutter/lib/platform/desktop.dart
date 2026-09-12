import 'dart:async';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../application/services.dart';
import '../domain/models.dart';
import '../ui/theme.dart';

class DesktopHost with TrayListener, WindowListener {
  DesktopHost(this.services, this.window);
  final AppServices services;
  final WindowController window;
  WindowController? widget;
  static Future<DesktopHost> initialize(AppServices services) async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1320, 900),
        minimumSize: Size(800, 600),
        title: '求是书院',
      ),
      () async {
        await windowManager.show();
      },
    );
    final host = DesktopHost(
      services,
      await WindowController.fromCurrentEngine(),
    );
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
          await windowManager.show();
          await windowManager.focus();
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
    await trayManager.setToolTip('求是书院');
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
  final input = TextEditingController();
  Timer? timer;
  List<Json> events = [];
  String answer = '', error = '';
  bool asking = false;
  late final host = WindowController.fromWindowId(widget.mainWindow);
  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
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
    input.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final data = object(await host.invokeMethod<dynamic>('schedule'));
      if (mounted) {
        setState(() {
          events = rows(data['events']);
          error = '';
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '日程暂不可用，请在主界面检查账号与网络。');
    }
  }

  Future<void> ask() async {
    final question = input.text.trim();
    if (asking || question.isEmpty) return;
    // 发送后立即清空输入框：主聊天窗（ui/chat.dart 的 send）同样如此，
    // 挂件这里此前漏掉了，导致消息发出后文字仍停留在输入框里。
    input.clear();
    setState(() => asking = true);
    try {
      final value = await host.invokeMethod<String>('ask', question);
      if (mounted) setState(() => answer = value ?? '');
    } catch (_) {
      if (mounted) setState(() => answer = '问答未完成，请重试。');
    } finally {
      if (mounted) setState(() => asking = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: paperTheme(),
    home: Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: const Color(0xcc12233f),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onPanStart: (_) => windowManager.startDragging(),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '求是 · 接下来',
                      style: TextStyle(color: paper, fontSize: 21),
                    ),
                  ),
                  IconButton(
                    onPressed: () => host.invokeMethod<void>('open'),
                    icon: const Icon(Icons.open_in_new, color: paper),
                  ),
                  IconButton(
                    onPressed: () => windowManager.hide(),
                    icon: const Icon(Icons.close, color: paper),
                  ),
                ],
              ),
            ),
            if (error.isNotEmpty)
              Text(error, style: const TextStyle(color: gold)),
            Expanded(
              child: ListView(
                children: [
                  for (final e in events)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        text(e, 'title'),
                        style: const TextStyle(color: paper),
                      ),
                      subtitle: Text(
                        '${e['date']} ${e['startTime']}-${e['endTime']}\n${e['location'] ?? ''}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                ],
              ),
            ),
            if (answer.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(answer, style: const TextStyle(color: paper)),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: input,
              onSubmitted: (_) => ask(),
              decoration: InputDecoration(
                hintText: '快捷问答 · 仅查询',
                suffixIcon: IconButton(
                  onPressed: asking ? null : ask,
                  icon: Icon(asking ? Icons.hourglass_empty : Icons.send),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
