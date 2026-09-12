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
}
