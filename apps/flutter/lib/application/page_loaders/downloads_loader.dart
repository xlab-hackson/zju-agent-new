import '../../domain/models.dart';
import '../services.dart';

Future<Json> loadDownloadsPage(AppServices s, {bool refresh = false}) async {
  var downloadCourses = <Json>[];
  try {
    final cached = await s.db.get('cache', 'courses');
    if (cached != null) downloadCourses = rows(cached['items']);
  } catch (_) {
    // A malformed cache must not hide the download records.
  }
  // Keep this page local-only. A download/delete must not wait for a
  // course refresh before the other download cards become interactive.
  return {
    'items': await s.db.list('downloads'),
    'courses': downloadCourses,
    'downloadDir': s.files.root.path,
    'defaultDownloadDir': s.files.defaultRoot.path,
    'isCustomDownloadDir': s.files.isCustomDirectory,
  };
}
