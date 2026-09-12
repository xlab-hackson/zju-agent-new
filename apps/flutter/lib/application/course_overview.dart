import '../domain/course_catalog.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import '../domain/timetable_options.dart';
import 'services.dart';

Future<Json> loadCourseOverview(
  AppServices s,
  String semester, {
  bool refresh = false,
  List<Json>? semestersOverride,
  List<Json>? rawCoursesOverride,
  List<TimetableEntry>? timetableOverride,
}) async {
  final semesters =
      semestersOverride ?? await s.campus.semesters(refresh: refresh);
  final rawCourses =
      rawCoursesOverride ?? await s.campus.courses(refresh: refresh);

  List<Json> allGrades = [];
  try {
    allGrades = await s.campus.grades('', refresh: refresh);
  } catch (_) {}
  if (allGrades.isEmpty) {
    try {
      final cached = await s.db.get('cache', 'grades:');
      if (cached != null) allGrades = rows(cached['items']);
    } catch (_) {}
  }

  List<Json> allEnrolled = [];
  try {
    allEnrolled = await s.campus.enrolledCourses('all', refresh: refresh);
  } catch (_) {}
  if (allEnrolled.isEmpty) {
    try {
      final cached = await s.db.get('cache', 'enrolled_courses:all');
      if (cached != null) allEnrolled = rows(cached['items']);
    } catch (_) {}
  }
  if (allEnrolled.isEmpty) {
    try {
      allEnrolled = await s.campus.enrolledCourses(semester, refresh: refresh);
    } catch (_) {}
  }

  List<TimetableEntry> ttEntries = timetableOverride ?? [];
  if (timetableOverride == null) {
    try {
      ttEntries = await s.campus.timetable(semester, refresh: refresh);
    } catch (_) {}
  }
  if (ttEntries.isEmpty) {
    try {
      final cached = await s.db.get('cache', 'timetable:$semester');
      if (cached != null) {
        ttEntries = rows(cached['items']).map(TimetableEntry.fromJson).toList();
      }
    } catch (_) {}
  }

  final semesterIdToZdbkCode = <String, String>{};
  for (final raw in rows(semesters)) {
    final rawId = text(raw, 'id').trim();
    final sName = text(raw, 'name').trim();
    final zdbkCode = semesterToId(sName) ?? semesterToId(rawId);
    if (rawId.isNotEmpty && zdbkCode != null) {
      semesterIdToZdbkCode[rawId] = zdbkCode;
    }
  }

  // Authoritative course list from 教务网 (ZDBK)
  final zdbkCoursesMap = <String, Map<String, dynamic>>{};
  void addOrUpdateZdbkCourse({
    required String name,
    required String semester,
    double credit = 0.0,
    String teacher = '',
    String xkkh = '',
    String location = '',
    String scheduleTime = '',
    String score = '',
    String gpa = '',
    bool selected = true,
  }) {
    final rawName = cleanCourseExtraSuffix(name);
    if (rawName.isEmpty) return;
    final normName = normalizeCourseName(rawName);
    final normSem = semesterToId(semester) ?? semester;
    final key = '$normSem|$normName';

    if (!zdbkCoursesMap.containsKey(key)) {
      zdbkCoursesMap[key] = {
        'name': rawName,
        'semesterId': normSem,
        'semester': normSem,
        'credit': credit,
        'teacher': teacher,
        'xkkh': xkkh,
        'location': location,
        'scheduleTime': scheduleTime,
        'selected': selected,
        'enrolled': selected,
        if (score.isNotEmpty) 'score': score,
        if (score.isNotEmpty) 'original': score,
        if (gpa.isNotEmpty) 'gpa': gpa,
        if (gpa.isNotEmpty) 'fivePoint': gpa,
      };
    } else {
      final existing = zdbkCoursesMap[key]!;
      if (!selected) {
        existing['selected'] = false;
        existing['enrolled'] = false;
      }
      if ((existing['credit'] as num? ?? 0) <= 0 && credit > 0) {
        existing['credit'] = credit;
      }
      if (text(existing, 'teacher').isEmpty && teacher.isNotEmpty) {
        existing['teacher'] = teacher;
      }
      if (text(existing, 'xkkh').isEmpty && xkkh.isNotEmpty) {
        existing['xkkh'] = xkkh;
      }
      if (text(existing, 'location').isEmpty && location.isNotEmpty) {
        existing['location'] = location;
      }
      if (text(existing, 'scheduleTime').isEmpty && scheduleTime.isNotEmpty) {
        existing['scheduleTime'] = scheduleTime;
      }
      if (score.isNotEmpty) {
        existing['score'] = score;
        existing['original'] = score;
      }
      if (gpa.isNotEmpty) {
        existing['gpa'] = gpa;
        existing['fivePoint'] = gpa;
      }
    }
  }

  // 1. Ingest enrolled courses from ZDBK (考签/已选课程)
  for (final e in allEnrolled) {
    final n = text(e, 'courseName', text(e, 'name')).trim();
    final sem = text(e, 'semester').trim();
    final cr = double.tryParse('${e['credit']}') ?? 0.0;
    final teacher = text(e, 'teacher').trim();
    final xkkh = text(e, 'xkkh').trim();
    final loc = text(e, 'location').trim();
    final isSel = isCourseSelected(e);
    addOrUpdateZdbkCourse(
      name: n,
      semester: sem.isNotEmpty ? sem : semester,
      credit: cr,
      teacher: teacher,
      xkkh: xkkh,
      location: loc,
      selected: isSel,
    );
  }

  // 2. Ingest timetable entries from ZDBK (教务网课表)
  for (final e in ttEntries) {
    final sem = e.semester.trim().isNotEmpty ? e.semester.trim() : semester;
    final weekText = e.weeks.isNotEmpty ? '${compressWeeks(e.weeks)}周' : '';
    final subText = e.subSemester.isNotEmpty ? e.subSemester : '';
    final details = [if (subText.isNotEmpty) subText, if (weekText.isNotEmpty) weekText].join(' ');
    final detailsStr = details.isNotEmpty ? ' ($details)' : '';
    final timeStr = e.weekday >= 1 && e.startSection >= 1
        ? '周${weekdayName(e.weekday)} ${e.startSection}-${e.endSection}节$detailsStr'
        : '';
    addOrUpdateZdbkCourse(
      name: e.courseName,
      semester: sem,
      credit: e.credit,
      teacher: e.teacher,
      xkkh: e.id,
      location: e.location,
      scheduleTime: timeStr,
      selected: e.selected && isCourseSelected(e.toJson()),
    );
  }

  // 3. Ingest cached timetables from DB
  try {
    final cachedTtIds = await s.db.ids('cache', prefix: 'timetable:');
    for (final cid in cachedTtIds) {
      final cItem = await s.db.get('cache', cid);
      final semFromCid = cid.replaceFirst('timetable:', '').trim();
      if (cItem != null && cItem['items'] is List) {
        for (final row in rows(cItem['items'])) {
          final entry = TimetableEntry.fromJson(row);
          final tName = text(row, 'courseName', entry.courseName).trim();
          final tTeacher = text(row, 'teacher', entry.teacher).trim();
          final tCredit = double.tryParse('${row['credit']}') ?? entry.credit;
          final tXkkh = text(row, 'classCode', text(row, 'xkkh', entry.id)).trim();
          final tLoc = text(row, 'location', text(row, 'room', entry.location)).trim();
          final tSem = semFromCid.isNotEmpty ? semFromCid : semester;
          final weekText = entry.weeks.isNotEmpty ? '${compressWeeks(entry.weeks)}周' : '';
          final subText = entry.subSemester.isNotEmpty ? entry.subSemester : '';
          final details = [if (subText.isNotEmpty) subText, if (weekText.isNotEmpty) weekText].join(' ');
          final detailsStr = details.isNotEmpty ? ' ($details)' : '';
          final timeStr = entry.weekday >= 1 && entry.startSection >= 1
              ? '周${weekdayName(entry.weekday)} ${entry.startSection}-${entry.endSection}节$detailsStr'
              : '';
          final isSel = entry.selected && isCourseSelected(row);
          if (tName.isNotEmpty) {
            addOrUpdateZdbkCourse(
              name: tName,
              semester: tSem,
              credit: tCredit,
              teacher: tTeacher,
              xkkh: tXkkh,
              location: tLoc,
              scheduleTime: timeStr,
              selected: isSel,
            );
          }
        }
      }
    }
  } catch (_) {}

  // 4. Ingest historical grades from ZDBK (全量成绩库)
  for (final g in allGrades) {
    final n = text(g, 'courseName').trim();
    final sem = text(g, 'semester').trim();
    final cr = double.tryParse('${g['credit']}') ?? 0.0;
    final teacher = text(g, 'teacher').trim();
    final original = text(g, 'original', text(g, 'score')).trim();
    final fivePoint = text(
      g,
      'fivePoint',
      text(g, 'gpa', text(g, 'jd')),
    ).trim();
    final xkkh = text(g, 'classCode', text(g, 'xkkh')).trim();
    addOrUpdateZdbkCourse(
      name: n,
      semester: sem,
      credit: cr,
      teacher: teacher,
      xkkh: xkkh,
      score: original,
      gpa: fivePoint,
    );
  }

  // 5. Match each unified 教务网 course with 学在浙大 (rawCourses)
  final courses = <Json>[];
  if (zdbkCoursesMap.isNotEmpty) {
    final matchedLearningCourseIds = <String>{};
    for (final entry in zdbkCoursesMap.entries) {
      final zItem = entry.value;
      final zName = text(zItem, 'name');
      final zNorm = normalizeCourseName(zName);
      final zSem = text(zItem, 'semesterId');
      final zXkkh = text(zItem, 'xkkh');

      Json? matchedLearning;

      // 5.1 Match by courseCode from xkkh
      if (zXkkh.isNotEmpty) {
        for (final lc in rawCourses) {
          final cCode = text(lc, 'courseCode').trim();
          if (cCode.isNotEmpty && zXkkh.contains(cCode)) {
            final lcSemId = text(lc, 'semesterId');
            final lcZdbkSem =
                semesterIdToZdbkCode[lcSemId] ?? semesterToId(lcSemId) ?? '';
            if (lcZdbkSem.isEmpty || lcZdbkSem == zSem) {
              matchedLearning = lc;
              break;
            }
          }
        }
      }

      // 5.2 Match by normalized name and semester
      if (matchedLearning == null) {
        for (final lc in rawCourses) {
          final lcName = text(lc, 'name').trim();
          final lcNorm = normalizeCourseName(lcName);
          if (lcNorm == zNorm) {
            final lcSemId = text(lc, 'semesterId');
            final lcZdbkSem =
                semesterIdToZdbkCode[lcSemId] ?? semesterToId(lcSemId) ?? '';
            if (lcZdbkSem == zSem) {
              matchedLearning = lc;
              break;
            }
          }
        }
      }

      // 5.3 Match by prefix or containment if normalized name matches base name
      if (matchedLearning == null) {
        for (final lc in rawCourses) {
          final lcName = text(lc, 'name').trim();
          final lcNorm = normalizeCourseName(lcName);
          if (lcNorm.startsWith(zNorm) || zNorm.startsWith(lcNorm)) {
            final lcSemId = text(lc, 'semesterId');
            final lcZdbkSem =
                semesterIdToZdbkCode[lcSemId] ?? semesterToId(lcSemId) ?? '';
            if (lcZdbkSem == zSem) {
              matchedLearning = lc;
              break;
            }
          }
        }
      }

      // 5.4 Match by normalized name or prefix if only 1 candidate exists
      if (matchedLearning == null) {
        final candidates = rawCourses.where((lc) {
          final lcNorm = normalizeCourseName(text(lc, 'name').trim());
          return lcNorm == zNorm ||
              lcNorm.startsWith(zNorm) ||
              zNorm.startsWith(lcNorm);
        }).toList();
        if (candidates.length == 1) {
          matchedLearning = candidates.first;
        }
      }

      final isCreated =
          matchedLearning != null && text(matchedLearning, 'id').isNotEmpty;
      if (isCreated) {
        matchedLearningCourseIds.add(text(matchedLearning, 'id'));
      }

      final isSelected = isCourseSelected(zItem);

      courses.add({
        ...zItem,
        'id': isCreated ? text(matchedLearning, 'id') : '',
        'selected': isSelected,
        'enrolled': isSelected,
        'learningZjuCreated': isCreated,
        if (isCreated && text(matchedLearning, 'teachingClassName').isNotEmpty)
          'teachingClassName': text(matchedLearning, 'teachingClassName'),
        if (text(zItem, 'teacher').isEmpty &&
            isCreated &&
            text(matchedLearning, 'teacher').isNotEmpty)
          'teacher': text(matchedLearning, 'teacher'),
      });
    }

    // 5.5 Add unmatched courses from rawCourses (学在浙大)
    for (final lc in rawCourses) {
      final lId = text(lc, 'id').trim();
      if (lId.isNotEmpty && matchedLearningCourseIds.contains(lId)) {
        continue;
      }
      final lName = text(lc, 'name').trim();
      if (lName.isEmpty) continue;
      final lNorm = normalizeCourseName(cleanCourseExtraSuffix(lName));
      final lcSemId = text(lc, 'semesterId').trim();
      final normSem =
          semesterIdToZdbkCode[lcSemId] ?? semesterToId(lcSemId) ?? lcSemId;
      if (zdbkCoursesMap.containsKey('$normSem|$lNorm')) {
        continue;
      }

      final isSel = isCourseSelected(lc);
      courses.add({
        ...lc,
        'semesterId': normSem,
        'semester': normSem,
        'selected': isSel,
        'enrolled': isSel,
        'learningZjuCreated': true,
      });
    }
  } else {
    // Fallback if no ZDBK course data is found at all (e.g. offline unit tests)
    for (final c in rawCourses) {
      final isSel = isCourseSelected(c);
      courses.add({
        ...c,
        'selected': isSel,
        'enrolled': isSel,
        'learningZjuCreated': c['learningZjuCreated'] == true ||
            (c['learningZjuCreated'] != false && text(c, 'id').isNotEmpty),
      });
    }
  }

  // 6. Merge semesters so tabs cover all historical semesters in 教务网
  final existingSemIds = <String>{
    for (final s in rows(semesters)) text(s, 'id'),
    for (final s in rows(semesters))
      if (semesterToId(text(s, 'name')) != null) semesterToId(text(s, 'name'))!,
  };
  final mergedSemesters = [...rows(semesters)];
  for (final c in courses) {
    final sId = text(c, 'semesterId', text(c, 'semester')).trim();
    if (sId.isNotEmpty && !existingSemIds.contains(sId)) {
      existingSemIds.add(sId);
      final yearMatch = RegExp(r'(\d{4}-\d{4})').firstMatch(sId);
      final year = yearMatch != null ? yearMatch.group(1)! : sId;
      final semLabel = sId.endsWith('-1')
          ? '$year学年秋冬学期'
          : (sId.endsWith('-2') ? '$year学年春夏学期' : sId);
      mergedSemesters.add({
        'id': sId,
        'name': semLabel,
        'isActive': sId == semester,
      });
    }
  }

  final time = await s.campus.oldestUpdatedAt(
    cacheKeys: [
      'semesters',
      'courses',
      'grades:',
      'enrolled_courses:all',
      'timetable:$semester',
    ],
  );

  return {
    'semesters': mergedSemesters,
    'courses': courses,
    'grades': allGrades,
    if (time != null) '_updatedAt': time.toIso8601String(),
  };
}
