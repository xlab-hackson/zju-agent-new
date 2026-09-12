import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'application/services.dart';
import 'platform/desktop.dart';
import 'ui/chat.dart';
import 'ui/pages_v2.dart';
import 'ui/settings.dart';
import 'ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    final window = await WindowController.fromCurrentEngine();
    if (window.arguments.startsWith('widget:')) {
      await prepareWidget();
      runApp(WidgetApp(mainWindow: window.arguments.substring(7)));
      return;
    }
  }
  try {
    final services = await AppServices.create();
    if (Platform.isWindows) await DesktopHost.initialize(services);
    runApp(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const CampusApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: paperTheme(),
        home: const Scaffold(
          body: Center(child: Text('本地数据初始化失败。请检查应用数据目录权限后重新启动。')),
        ),
      ),
    );
  }
}

final appRouter = GoRouter(
  routes: [
    for (final route in [
      '/',
      '/courses',
      '/assignments',
      '/exams',
      '/school-info',
      '/downloads',
      '/settings',
      '/setup',
      '/classroom',
    ])
      GoRoute(
        path: route,
        builder: (context, state) => CampusShell(path: route),
      ),
    for (final alias in ['/dashboard', '/toolbox', '/chat'])
      GoRoute(path: alias, redirect: (context, state) => '/'),
  ],
);

class CampusApp extends StatelessWidget {
  const CampusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: '求是书院',
    debugShowCheckedModeBanner: false,
    theme: paperTheme(),
    routerConfig: appRouter,
  );
}

const navigation = [
  ('/', '工作台', 'notebook-desk'),
  ('/courses', '课程表', 'calendar-grid'),
  ('/assignments', '作业', 'checklist-paper'),
  ('/exams', '考试', 'exam-paper'),
  ('/school-info', '通知', 'announcement-horn'),
];

const secondaryNavigation = [
  ('/downloads', '下载', 'folder'),
  ('/settings', '设置', 'cartoon-settings'),
];

class CampusShell extends ConsumerWidget {
  const CampusShell({super.key, required this.path});
  final String path;

  Widget icon(String name, {Color? color}) => SvgPicture.asset(
    'assets/icons/$name.svg',
    width: 22,
    height: 22,
    colorFilter: color == null
        ? null
        : ColorFilter.mode(color, BlendMode.srcIn),
  );

  int mobileIndex() {
    final primary = navigation.indexWhere((n) => n.$1 == path);
    if (primary >= 0) return primary;
    // 下载与设置只保留在窄屏右上角，不占用底部五项主导航的位置。
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider),
        desktop = MediaQuery.sizeOf(context).width >= 1024;
    final feature = path != '/settings' && path != '/setup';
    final content = feature
        ? FeaturePage(key: ValueKey(path), services: services, page: path)
        : SettingsPage(
            key: ValueKey(path),
            services: services,
            setup: path == '/setup',
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            openChat(context, services),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            openChat(context, services),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktop)
                SizedBox(
                  width: 240,
                  child: _DesktopSidebar(
                    path: path,
                    icon: icon,
                    onNavigate: context.go,
                  ),
                ),
              Expanded(
                child: feature
                    ? content
                    : SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          desktop ? 38 : 16,
                          desktop ? 32 : 24,
                          desktop ? 38 : 16,
                          100,
                        ),
                        child: content,
                      ),
              ),
            ],
          ),
          appBar: desktop
              ? null
              : AppBar(
                  title: const Text('求是书院'),
                  actions: [
                    IconButton(
                      tooltip: '下载',
                      onPressed: () => context.go('/downloads'),
                      icon: const Icon(Icons.folder_outlined),
                    ),
                    IconButton(
                      tooltip: '设置',
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => openChat(context, services),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('问学\n⌘K', textAlign: TextAlign.center),
            backgroundColor: seal,
            foregroundColor: paperCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: mobileIndex(),
                  onDestinationSelected: (i) => context.go(navigation[i].$1),
                  destinations: [
                    for (final n in navigation)
                      NavigationDestination(icon: icon(n.$3), label: n.$2),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.path,
    required this.icon,
    required this.onNavigate,
  });
  final String path;
  final Widget Function(String, {Color? color}) icon;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xff12233f), Color(0xff09182f)],
      ),
      border: Border(right: BorderSide(color: Color(0x66b08d3e), width: 1.5)),
    ),
    padding: const EdgeInsets.fromLTRB(20, 20, 18, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: seal,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: paperCard, width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Color(0x553b1b19), offset: Offset(2, 3)),
                ],
              ),
              child: const Text(
                '求是',
                style: TextStyle(
                  color: paperCard,
                  fontSize: 20,
                  fontFamily: 'MaShanZheng',
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '求是书院',
                  style: TextStyle(
                    color: paper,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
                Text(
                  'ZJU CAMPUS AGENT',
                  style: TextStyle(
                    color: gold,
                    fontSize: 9,
                    letterSpacing: 2.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            const Text(
              '学业导航',
              style: TextStyle(color: gold, fontSize: 11, letterSpacing: 4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [gold, Colors.transparent]),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < navigation.length; i++)
          _NavTile(
            item: navigation[i],
            juan: ['壹', '贰', '叁', '肆', '伍'][i],
            selected: path == navigation[i].$1,
            icon: icon,
            onTap: () => onNavigate(navigation[i].$1),
          ),
        const Spacer(),
        const Center(
          child: Text(
            '求是创新',
            style: TextStyle(
              color: gold,
              fontFamily: 'MaShanZheng',
              fontSize: 20,
              letterSpacing: 6,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(color: Color(0x55b08d3e)),
        Row(
          children: [
            for (final item in secondaryNavigation)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton.icon(
                    onPressed: () => onNavigate(item.$1),
                    icon: icon(item.$3, color: paper),
                    label: Text(item.$2),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: paper,
                      side: const BorderSide(color: Color(0x55b08d3e)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.juan,
    required this.selected,
    required this.icon,
    required this.onTap,
  });
  final (String, String, String) item;
  final String juan;
  final bool selected;
  final Widget Function(String, {Color? color}) icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? blue.withValues(alpha: .35) : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: selected ? gold : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              juan,
              style: TextStyle(
                color: selected ? gold : gold.withValues(alpha: .55),
                fontSize: 10,
              ),
            ),
          ),
          icon(item.$3, color: selected ? paper : paper.withValues(alpha: .72)),
          const SizedBox(width: 12),
          Text(
            item.$2,
            style: TextStyle(
              color: selected ? paper : paper.withValues(alpha: .65),
              fontSize: 14,
              letterSpacing: 2,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    ),
  );
}
