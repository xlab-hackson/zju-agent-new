import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/database.dart';
import '../data/credentials.dart';
import '../data/campus_session.dart';
import '../domain/page_context.dart';
import 'agent.dart';
import 'campus.dart';
import 'files.dart';
import 'knowledge.dart';

final servicesProvider = Provider<AppServices>(
  (ref) => throw StateError('Services must be initialized before rendering.'),
);

/// 解析下载根目录。
///
/// 优先级：设置在 `settings/app.downloadDir` 里选定的目录 → 系统「下载」目录
/// → 应用支持目录。后两级回退是必要的：`path_provider` 在 Android 上不提供
/// 下载目录，其他平台上调用也可能直接抛异常。
Future<Directory> downloadDirectory(
  AgentDatabase db,
  Directory support,
) async {
  final settings = await db.get('settings', 'app') ?? {};
  final configured = '${settings['downloadDir'] ?? ''}'.trim();
  if (configured.isNotEmpty) return Directory(configured);
  try {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
  } catch (_) {
    // 平台不提供下载目录，回退到应用支持目录。
  }
  return Directory(p.join(support.path, 'downloads'));
}

class AppServices {
  AppServices(
    this.db,
    this.secrets,
    this.campus,
    this.files,
    this.backups,
    this.agent,
  );
  final AgentDatabase db;
  final SecretStore secrets;
  final CampusService campus;
  final FileService files;
  final BackupService backups;
  final AgentService agent;
  final Set<String> _initialRefreshes = <String>{};
  PageContext? _currentPageContext;

  /// 用户当前所在界面的实时感知上下文
  PageContext? get currentPageContext => _currentPageContext;

  /// Target tab for assignments page navigation (e.g. 'urgent', 'relaxed', 'submitted')
  String targetAssignmentTab = 'all';

  /// 更新用户当前界面的感知上下文
  void updatePageContext(PageContext context) {
    _currentPageContext = context;
  }

  /// Claims the one automatic refresh allowed for a page in this app run.
  ///
  /// Keeping this state above individual page widgets prevents navigating
  /// away and back from issuing another automatic request.
  bool claimInitialRefresh(String key) => _initialRefreshes.add(key);

  static Future<AppServices> create() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    final db = AgentDatabase(File(p.join(support.path, 'agent.db'))),
        secrets = SecureSecrets();
    final campus = CampusService(CampusSession(secrets), db);
    final dir = Directory(p.join(support.path, 'downloads'));
    await dir.create(recursive: true);
    final files = FileService(campus, dir), guide = await GuideIndex.load();
    // Never replay interrupted downloads or confirmations after process death.
    for (final c in await db.list('confirmations')) {
      if (c['status'] == 'consumed') {
        await db.put('confirmations', '${c['id']}', {
          ...c,
          'status': 'interrupted',
        });
      }
    }
    for (final d in await db.list('downloads')) {
      if (d['status'] == 'downloading') {
        await db.put('downloads', '${d['id']}', {
          ...d,
          'status': 'interrupted',
        });
      }
    }
    late final AppServices services;
    final agent = AgentService(
      campus,
      files,
      guide,
      getPageContext: () => services.currentPageContext,
    );
    services = AppServices(
      db,
      secrets,
      campus,
      files,
      BackupService(db, files),
      agent,
    );
    return services;
  }

  Future<void> logout() async {
    agent.cancelAll();
    await campus.session.reset();
    _initialRefreshes.clear();
    _currentPageContext = null;
    await secrets.delete('campus');
    await db.remove('cache');
    await db.remove('confirmations');
  }

  /// 切换下载保存位置并持久化；传 null 或空串表示恢复默认。
  ///
  /// 返回切换后的目录。已有下载记录保存的是相对旧根目录的路径，不会跟着
  /// 搬家，会因此在下载页显示为「已被移除」。
  Future<Directory> applyDownloadDirectory(String? path) async {
    final settings = {...await db.get('settings', 'app') ?? <String, dynamic>{}};
    final wanted = path?.trim() ?? '';
    if (wanted.isEmpty) {
      settings.remove('downloadDir');
    } else {
      settings['downloadDir'] = wanted;
    }
    // 先落库再解析：downloadDirectory 依赖已经写入的设置。
    await db.put('settings', 'app', settings);
    final support = await getApplicationSupportDirectory();
    final next = await downloadDirectory(db, support);
    await files.moveRoot(next);
    return next;
  }
}
