import 'course_catalog.dart';
import 'models.dart';
import 'schedule.dart';

double _parseNum(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

class GradeStats {
  final double gpa;
  final double totalCredits;
  final double avgScore;
  final double semesterCredits;
  final bool hasGrades;

  const GradeStats({
    required this.gpa,
    required this.totalCredits,
    required this.avgScore,
    required this.semesterCredits,
    required this.hasGrades,
  });

  bool get hasData => hasGrades;
  double get totalEarnedCredits => totalCredits;
  double get averageScore => avgScore;

  static GradeStats compute({
    required List<Json> grades,
    required String currentSemester,
    List<String> currentCourseNames = const [],
    double timetableCredits = 0.0,
  }) {
    if (grades.isEmpty) {
      return GradeStats(
        gpa: 0,
        totalCredits: 0,
        avgScore: 0,
        semesterCredits: timetableCredits,
        hasGrades: false,
      );
    }

    double gpaWeightedSum = 0;
    double gpaCreditSum = 0;
    double earnedCreditSum = 0;
    double scoreWeightedSum = 0;
    double scoreCreditSum = 0;
    double semCreditSum = 0;

    for (final g in grades) {
      final credit = _parseNum(g['credit']);
      final fivePoint = _parseNum(g['fivePoint']);
      final original = text(g, 'original');
      final included = g['creditIncluded'] == true;
      final gpaIncluded = g['gpaIncluded'] == true;
      final id = text(g, 'id');
      final sem = text(g, 'semester');
      final xkkh = text(g, 'xkkh');
      final semFromXkkh =
          RegExp(
            r'(\d{4}-\d{4}-[12])',
          ).firstMatch(xkkh.isNotEmpty ? xkkh : id)?[1] ??
          '';

      // Check if passed for earned credits
      final scoreVal = double.tryParse(original);
      final isFailing =
          original == '不合格' || (scoreVal != null && scoreVal < 60);
      if (included && !isFailing && credit > 0) {
        earnedCreditSum += credit;
      }

      // GPA calculation
      if (gpaIncluded && credit > 0 && fivePoint >= 0) {
        gpaWeightedSum += fivePoint * credit;
        gpaCreditSum += credit;
      }

      // Average score calculation (from numerical scores)
      if (gpaIncluded && credit > 0 && scoreVal != null && scoreVal >= 0) {
        scoreWeightedSum += scoreVal * credit;
        scoreCreditSum += credit;
      }

      // Semester credit calculation
      final isCurrentSem =
          currentSemester.isNotEmpty &&
          (sem == currentSemester ||
              semFromXkkh == currentSemester ||
              id.contains(currentSemester) ||
              xkkh.contains(currentSemester));
      if (isCurrentSem && credit > 0) {
        semCreditSum += credit;
      }
    }

    // If timetableCredits > 0 (authoritative enrolled / timetable course credits),
    // always prioritize it over partial or early grades in the current ongoing semester.
    if (timetableCredits > 0) {
      semCreditSum = timetableCredits;
    }

    // If semester credits not found directly in currentSemester grades, try matching by course names
    if (semCreditSum == 0 && currentCourseNames.isNotEmpty) {
      final courseCreditMap = <String, double>{};
      for (final g in grades) {
        final name = text(g, 'courseName').trim();
        final cr = _parseNum(g['credit']);
        if (name.isNotEmpty && cr > 0) {
          courseCreditMap[name] = cr;
          courseCreditMap[name
                  .replaceAll(RegExp(r'[（\(].*?[）\)]'), '')
                  .trim()] =
              cr;
        }
      }
      final matched = <String>{};
      for (final rawName in currentCourseNames) {
        final name = rawName.trim();
        final clean = name.replaceAll(RegExp(r'[（\(].*?[）\)]'), '').trim();
        if (matched.contains(name) ||
            (clean.isNotEmpty && matched.contains(clean))) {
          continue;
        }
        if (courseCreditMap.containsKey(name)) {
          semCreditSum += courseCreditMap[name]!;
          matched.add(name);
        } else if (clean.isNotEmpty && courseCreditMap.containsKey(clean)) {
          semCreditSum += courseCreditMap[clean]!;
          matched.add(clean);
        }
      }
    }

    final finalGpa = gpaCreditSum > 0 ? (gpaWeightedSum / gpaCreditSum) : 0.0;
    final finalAvgScore = scoreCreditSum > 0
        ? (scoreWeightedSum / scoreCreditSum)
        : 0.0;

    return GradeStats(
      gpa: finalGpa,
      totalCredits: earnedCreditSum,
      avgScore: finalAvgScore,
      semesterCredits: semCreditSum,
      hasGrades: true,
    );
  }
}

class SemesterGradeStats {
  final String selected;
  final double gpa;
  final double earnedCredits;
  final double enrolledCredits;
  final double avgScore;
  final bool hasGrades;
  final int totalCourses;
  final int gradedCourses;

  const SemesterGradeStats({
    required this.selected,
    required this.gpa,
    required this.earnedCredits,
    required this.enrolledCredits,
    required this.avgScore,
    required this.hasGrades,
    required this.totalCourses,
    required this.gradedCourses,
  });
}

SemesterGradeStats computeSemesterGradeStats({
  required String selected,
  required List<Json> courses,
  required List<Json> allCourses,
  required List<Json> allGrades,
  required Set<String> matchingIds,
}) {
  if (selected == 'all') {
    if (allGrades.isNotEmpty) {
      final gs = GradeStats.compute(grades: allGrades, currentSemester: '');
      final totalEnrolled = courseCredits(allCourses);
      int gradedCount = 0;
      for (final g in allGrades) {
        final orig = text(g, 'original', text(g, 'score')).trim();
        if (orig.isNotEmpty && !['弃修', '缓考', '待录'].contains(orig)) {
          gradedCount++;
        }
      }
      return SemesterGradeStats(
        selected: selected,
        gpa: gs.gpa,
        earnedCredits: gs.totalCredits,
        enrolledCredits: totalEnrolled > 0 ? totalEnrolled : gs.totalCredits,
        avgScore: gs.avgScore,
        hasGrades: gs.hasGrades && gs.gpa > 0,
        totalCourses: allCourses.length,
        gradedCourses: gradedCount > 0
            ? gradedCount
            : allCourses.where((c) => text(c, 'score').isNotEmpty).length,
      );
    }
  }

  final normZdbkSem = semesterToId(selected) ?? selected;

  final semGrades = allGrades.where((g) {
    final sem = text(g, 'semester').trim();
    final xkkh = text(g, 'xkkh').trim();
    final semFromXkkh =
        RegExp(r'(\d{4}-\d{4}-[12])').firstMatch(xkkh)?[1] ?? sem;
    return matchingIds.contains(sem) ||
        matchingIds.contains(semFromXkkh) ||
        (normZdbkSem.isNotEmpty &&
            (sem == normZdbkSem || semFromXkkh == normZdbkSem));
  }).toList();

  if (semGrades.isNotEmpty) {
    final gs = GradeStats.compute(
      grades: semGrades,
      currentSemester: normZdbkSem,
    );
    final totalEnrolled = courseCredits(courses);
    int gradedCount = 0;
    for (final g in semGrades) {
      final orig = text(g, 'original', text(g, 'score')).trim();
      if (orig.isNotEmpty && !['弃修', '缓考', '待录'].contains(orig)) {
        gradedCount++;
      }
    }
    return SemesterGradeStats(
      selected: selected,
      gpa: gs.gpa,
      earnedCredits: gs.totalCredits,
      enrolledCredits: totalEnrolled > 0 ? totalEnrolled : gs.totalCredits,
      avgScore: gs.avgScore,
      hasGrades: gs.hasGrades && gs.gpa > 0,
      totalCourses: courses.length,
      gradedCourses: gradedCount,
    );
  }

  double gpaWeighted = 0;
  double gpaCreditSum = 0;
  double scoreWeighted = 0;
  double scoreCreditSum = 0;
  double earnedCreditSum = 0;
  final totalEnrolled = courseCredits(courses);
  int gradedCount = 0;

  for (final c in courses) {
    final cr = double.tryParse('${c['credit']}') ?? 0.0;
    final scoreStr = text(c, 'score', text(c, 'original')).trim();
    final gpaVal = double.tryParse(text(c, 'gpa', text(c, 'fivePoint')).trim());
    final scoreVal = double.tryParse(scoreStr);

    if (scoreStr.isNotEmpty && !['弃修', '缓考', '待录'].contains(scoreStr)) {
      gradedCount++;
      final isFailing =
          scoreStr == '不合格' || (scoreVal != null && scoreVal < 60);
      if (!isFailing && cr > 0) {
        earnedCreditSum += cr;
      }
      if (gpaVal != null &&
          gpaVal >= 0 &&
          cr > 0 &&
          !['合格', '不合格'].contains(scoreStr)) {
        gpaWeighted += gpaVal * cr;
        gpaCreditSum += cr;
      }
      if (scoreVal != null && scoreVal >= 0 && cr > 0) {
        scoreWeighted += scoreVal * cr;
        scoreCreditSum += cr;
      }
    }
  }

  final finalGpa = gpaCreditSum > 0 ? (gpaWeighted / gpaCreditSum) : 0.0;
  final finalAvg = scoreCreditSum > 0 ? (scoreWeighted / scoreCreditSum) : 0.0;

  return SemesterGradeStats(
    selected: selected,
    gpa: finalGpa,
    earnedCredits: earnedCreditSum,
    enrolledCredits: totalEnrolled,
    avgScore: finalAvg,
    hasGrades: gpaCreditSum > 0,
    totalCourses: courses.length,
    gradedCourses: gradedCount,
  );
}
