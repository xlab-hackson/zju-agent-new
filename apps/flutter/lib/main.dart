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
import 'ui/pages.dart';
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider),
        desktop = MediaQuery.sizeOf(context).width >= 1024;
    final index = navigation.indexWhere((n) => n.$1 == path);
    final content = path == '/settings' || path == '/setup'
        ? SettingsPage(
            key: ValueKey(path),
            services: services,
            setup: path == '/setup',
          )
        : FeaturePage(key: ValueKey(path), services: services, page: path);
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
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (desktop)
                Container(
                  width: 240,
                  color: const Color(0xff12233f),
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            color: seal,
                            child: const Text(
                              '求是',
                              style: TextStyle(
                                color: paperCard,
                                fontSize: 24,
                                fontFamily: 'MaShanZheng',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '求是书院',
                                style: TextStyle(
                                  color: paper,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'ZJU CAMPUS AGENT',
                                style: TextStyle(
                                  color: gold,
                                  fontSize: 9,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 42),
                      const Text('学 业 导 航', style: TextStyle(color: gold)),
                      const SizedBox(height: 14),
                      for (var i = 0; i < navigation.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                            selected: path == navigation[i].$1,
                            selectedTileColor: blue.withValues(alpha: .4),
                            leading: icon(navigation[i].$3, color: paper),
                            title: Text(
                              '${['壹', '贰', '叁', '肆', '伍'][i]}  ${navigation[i].$2}',
                              style: const TextStyle(color: paper),
                            ),
                            onTap: () => context.go(navigation[i].$1),
                          ),
                        ),
                      const Spacer(),
                      const Center(
                        child: Text(
                          '求是创新',
                          style: TextStyle(
                            color: gold,
                            fontFamily: 'MaShanZheng',
                            fontSize: 24,
                            letterSpacing: 6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Divider(color: gold),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => context.go('/downloads'),
                            child: const Text(
                              '下载',
                              style: TextStyle(color: paper),
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/settings'),
                            child: const Text(
                              '设置',
                              style: TextStyle(color: paper),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: CustomPaint(
                  painter: PaperLines(),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      desktop ? 38 : 16,
                      desktop ? 32 : 12,
                      desktop ? 38 : 16,
                      100,
                    ),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => openChat(context, services),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('问学'),
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: index < 0 ? 0 : index,
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
