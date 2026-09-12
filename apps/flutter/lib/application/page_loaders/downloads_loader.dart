import '../../domain/models.dart';
import '../files.dart';
import '../services.dart';

Future<Json> loadDownloadsPage(AppServices s, {bool refresh = false}) async {
  var downloadCourses = <Json>[];
  try {
    final cached = await s.db.get('cache', 'courses');
    if (cached != null) downloadCourses = rows(cached['items']);
  } catch (_) {
    // A malformed cache must not hide the download records.
  }
  // 每条记录带上文件是否仍在当前下载根目录下。换过下载目录后旧记录会落到
  // false，页面据此显示「已被移除」，而不是等用户点开才报错。
  final items = <Json>[];
  for (final record in await s.db.list('downloads')) {
    items.add({
      ...record,
      'exists': await localFileExists(
        s.files.root.path,
        text(record, 'relativePath'),
      ),
    });
  }
  // Keep this page local-only. A download/delete must not wait for a
  // course refresh before the other download cards become interactive.
  return {
    'items': items,
    'courses': downloadCourses,
    'downloadDir': s.files.root.path,
    'defaultDownloadDir': s.files.defaultRoot.path,
    'isCustomDownloadDir': s.files.isCustomDirectory,
  };
}
