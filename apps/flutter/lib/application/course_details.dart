import '../domain/models.dart';
import '../domain/timetable_options.dart';
import 'services.dart';

class CourseDetails {
  CourseDetails({
    required this.services,
    required this.semester,
    required this.data,
    this.overviewData,
  });
  final AppServices services;
  final String semester;
  final Future<Json> data;
  final Future<Json>? overviewData;
  AppServices get s => services;
  Future<Json> enrichCourse(Json c) async {
    final name = text(c, 'name');
    final teacher = text(c, 'teacher');
    final location = text(c, 'location');
    final scheduleTime = text(c, 'scheduleTime');
    if (teacher.isNotEmpty && location.isNotEmpty && scheduleTime.isNotEmpty) {
      return c;
    }

    List<TimetableEntry> ttEntries = [];
    try {
      final d = await data;
      if (d['timetable'] is List) {
        ttEntries = rows(d['timetable']).map(TimetableEntry.fromJson).toList();
      }
    } catch (_) {}
    if (ttEntries.isEmpty) {
      try {
        final cached = await s.db.get('cache', 'timetable:$semester');
        if (cached != null) {
          ttEntries = rows(
            cached['items'],
          ).map(TimetableEntry.fromJson).toList();
        }
      } catch (_) {}
    }

    final cleanName = name.replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
    TimetableEntry? matched;
    for (final e in ttEntries) {
      if (e.courseName == name) {
        matched = e;
        break;
      }
    }
    if (matched == null) {
      for (final e in ttEntries) {
        final eClean = e.courseName
            .replaceAll(RegExp(r'[（\(].*?[）\)]'), '')
            .trim();
        if (eClean == cleanName ||
            e.courseName.contains(cleanName) ||
            cleanName.contains(e.courseName)) {
          matched = e;
          break;
        }
      }
    }

    if (matched == null) return c;

    final weekText = matched.weeks.isNotEmpty
        ? '${compressWeeks(matched.weeks)} 周'
        : '';
    final subText = matched.subSemester.isNotEmpty
        ? '${matched.subSemester} '
        : '';
    final timeStr =
        '周${weekdayName(matched.weekday)} ${matched.startSection}-${matched.endSection}节 ($subText$weekText)';

    return {
      ...c,
      if (teacher.isEmpty && matched.teacher.isNotEmpty)
        'teacher': matched.teacher,
      if (location.isEmpty && matched.location.isNotEmpty)
        'location': matched.location,
      if (scheduleTime.isEmpty) 'scheduleTime': timeStr,
      if ((double.tryParse('${c['credit']}') ?? 0.0) <= 0 && matched.credit > 0)
        'credit': matched.credit,
    };
  }

  Future<Json> timetableCourse(TimetableEntry entry) async {
    List<Json> coursesList = [];
    try {
      final od = await overviewData;
      if (od != null) coursesList = rows(od['courses'] ?? []);
    } catch (_) {}
    if (coursesList.isEmpty) {
      try {
        final cached = await s.db.get('cache', 'courses');
        if (cached != null) coursesList = rows(cached['items']);
      } catch (_) {}
    }
    final matched = _findCourseByName(coursesList, entry.courseName);
    final weekText = entry.weeks.isNotEmpty
        ? '${compressWeeks(entry.weeks)} 周'
        : '';
    final subText = entry.subSemester.isNotEmpty ? '${entry.subSemester} ' : '';
    final timeStr =
        '周${weekdayName(entry.weekday)} ${entry.startSection}-${entry.endSection}节 ($subText$weekText)';
    final enriched = {
      ...?matched,
      'name': entry.courseName,
      if (entry.teacher.isNotEmpty) 'teacher': entry.teacher,
      if (entry.location.isNotEmpty) 'location': entry.location,
      'scheduleTime': timeStr,
      if (entry.credit > 0) 'credit': entry.credit,
      if (matched == null || matched['learningZjuCreated'] == false)
        'learningZjuCreated': false,
    };
    return enriched;
  }

  Future<Json?> eventCourse(Json event) async {
    final name = text(event, 'title', text(event, 'courseName'));
    if (name.isEmpty) return null;
    List<Json> coursesList = [];
    try {
      final d = await data;
      coursesList = rows(d['courses'] ?? []);
    } catch (_) {}
    if (coursesList.isEmpty) {
      try {
        final cached = await s.db.get('cache', 'courses');
        if (cached != null) coursesList = rows(cached['items']);
      } catch (_) {}
    }
    final matched = _findCourseByName(coursesList, name);
    final timeStr =
        '${text(event, 'date')} ${text(event, 'startTime')}-${text(event, 'endTime')}';
    final enriched = {
      ...?matched,
      'name': name,
      if (text(event, 'teacher').isNotEmpty) 'teacher': text(event, 'teacher'),
      if (text(event, 'location').isNotEmpty)
        'location': text(event, 'location'),
      'scheduleTime': timeStr,
      if (matched == null || matched['learningZjuCreated'] == false)
        'learningZjuCreated': false,
    };
    return enriched;
  }

  static Json? _findCourseByName(List<Json> courses, String name) {
    if (name.isEmpty) return null;
    final cleanName = name.replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
    for (final c in courses) {
      final cName = text(c, 'name');
      if (cName == name) return c;
    }
    for (final c in courses) {
      final cName = text(
        c,
        'name',
      ).replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
      if (cName == cleanName) return c;
    }
    for (final c in courses) {
      final cName = text(c, 'name');
      if (cName.contains(cleanName) || cleanName.contains(cName)) return c;
    }
    return null;
  }
}
