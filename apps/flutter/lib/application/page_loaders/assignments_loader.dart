import '../../domain/models.dart';
import '../services.dart';
import 'cache_timestamp.dart';

Future<Json> loadAssignmentsPage(AppServices s, {bool refresh = false}) async {
  final courseCandidates = await s.campus.courses(refresh: refresh);
  final items = await s.campus.assignments(
    courseCandidates: courseCandidates,
    refresh: refresh,
  );
  final assignmentCacheKeys = courseCandidates
      .map((course) => text(course, 'id').trim())
      .where((courseId) => courseId.isNotEmpty)
      .map((courseId) => 'assignments:$courseId');
  return {
    'items': items,
    '_updatedAt': await pageUpdatedAt(
      s,
      cacheKeys: ['courses', ...assignmentCacheKeys],
    ),
  };
}
