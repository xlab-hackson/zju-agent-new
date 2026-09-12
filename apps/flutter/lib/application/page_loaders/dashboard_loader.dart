import '../../domain/models.dart';
import '../course_overview.dart';
import '../services.dart';
import 'cache_timestamp.dart';

Future<Json> loadDashboardPage(
  AppServices s,
  String semester, {
  bool refresh = false,
}) async {
  final campus = await s.secrets.read('campus');
  final hasCampusCredential = campus != null;
  final providers = await s.secrets.read('providers');
  final result = <String, dynamic>{
    'settings': await s.db.get('settings', 'app') ?? {},
    'hasCampusCredential': hasCampusCredential,
    'campusStatus': hasCampusCredential
        ? s.campus.session.authStatus
        : 'missing',
    'hasModel': rows(providers?['items'] ?? []).isNotEmpty,
  };
  Json? upcomingData;
  try {
    // upcoming() already loads the calendar, timetable, exams and
    // assignments needed by the dashboard. Keep this result as the
    // shared source for the cards instead of fetching each dataset
    // again below.
    upcomingData = await s.campus.upcoming(refresh: refresh);
    result['schedule'] = upcomingData;
    result['assignments'] = rows(upcomingData['assignments'] ?? []);
    result['exams'] = rows(upcomingData['currentExams'] ?? []);
  } on AppError catch (e) {
    result['scheduleError'] = e.message;
  }

  try {
    final schedule = upcomingData;
    result['courseOverview'] = await loadCourseOverview(
      s,
      semester,
      refresh: refresh,
      semestersOverride: schedule == null
          ? null
          : rows(schedule['semesters'] ?? []),
      rawCoursesOverride: schedule == null
          ? null
          : rows(schedule['courses'] ?? []),
      timetableOverride: schedule == null
          ? null
          : rows(
              schedule['currentTimetable'] ?? [],
            ).map(TimetableEntry.fromJson).toList(),
    );
  } on AppError catch (e) {
    result['courseOverviewError'] = e.message;
  }
  result['campusStatus'] = hasCampusCredential
      ? s.campus.session.authStatus
      : 'missing';
  final relevantSemesters = <String>{semester};
  final semesterIds = upcomingData?['semesterIds'];
  if (semesterIds is List) {
    relevantSemesters.addAll(
      semesterIds
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty),
    );
  }
  final assignmentCacheKeys = <String>{};
  final assignmentCourseIds = upcomingData?['assignmentCourseIds'];
  if (assignmentCourseIds is List) {
    assignmentCacheKeys.addAll(
      assignmentCourseIds
          .map((value) => '$value'.trim())
          .where((value) => value.isNotEmpty)
          .map((value) => 'assignments:$value'),
    );
  }
  final cacheKeys = [
    'semesters',
    'courses',
    'enrolled_courses:all',
    'grades:',
    ...assignmentCacheKeys,
    for (final id in relevantSemesters) ...['timetable:$id', 'exams:$id'],
  ];
  result['_updatedAt'] = await pageUpdatedAt(
    s,
    cacheKeys: cacheKeys,
    calendarKeys: relevantSemesters,
  );
  result['_hasStaleData'] = [
    ...cacheKeys,
    for (final id in relevantSemesters) 'calendar:$id',
  ].any(s.campus.stale.contains);
  return result;
}
