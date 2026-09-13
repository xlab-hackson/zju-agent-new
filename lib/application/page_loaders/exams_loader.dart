import '../../domain/models.dart';
import '../services.dart';
import 'cache_timestamp.dart';

Future<Json> loadExamsPage(
  AppServices s,
  String semester, {
  bool refresh = false,
}) async {
  final items = await s.campus.exams(semester, refresh: refresh);
  final semesters = await s.campus.semesters(refresh: refresh);
  return {
    'items': items,
    'semesters': semesters,
    '_updatedAt': await pageUpdatedAt(
      s,
      cacheKeys: ['exams:$semester', 'semesters'],
    ),
  };
}
