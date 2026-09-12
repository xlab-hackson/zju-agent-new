import '../../domain/models.dart';
import '../services.dart';
import 'cache_timestamp.dart';

Future<Json> loadCoursesPage(
  AppServices s,
  String semester, {
  bool refresh = false,
}) async {
  final semesters = await s.campus.semesters(refresh: refresh);
  final timetable = (await s.campus.timetable(
    semester,
    refresh: refresh,
  )).map((e) => e.toJson()).toList();
  return {
    'semesters': semesters,
    'timetable': timetable,
    '_updatedAt': await pageUpdatedAt(
      s,
      cacheKeys: ['semesters', 'timetable:$semester'],
    ),
  };
}
