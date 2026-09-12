import 'models.dart';
import 'schedule.dart';

Set<String> matchingSemesterIds(List<Json> semesters, String selected) {
  final ids = <String>{selected};
  for (final semester in semesters) {
    final rawId = text(semester, 'id').trim();
    final normalizedName = semesterToId(text(semester, 'name'));
    final normalizedId = semesterToId(rawId);
    if (rawId == selected ||
        normalizedName == selected ||
        normalizedId == selected) {
      if (rawId.isNotEmpty) ids.add(rawId);
      if (normalizedName != null) ids.add(normalizedName);
      if (normalizedId != null) ids.add(normalizedId);
    }
  }
  final normalizedSelected = semesterToId(selected);
  if (normalizedSelected != null) ids.add(normalizedSelected);
  return ids;
}

List<Json> coursesForSemester(
  List<Json> allCourses,
  List<Json> semesters,
  String selected,
) {
  if (selected == 'all') return allCourses;
  final matchingIds = matchingSemesterIds(semesters, selected);
  return allCourses.where((course) {
    final semesterId = text(course, 'semesterId').trim();
    final semester = text(course, 'semester').trim();
    final normalizedSemesterId = semesterToId(semesterId) ?? semesterId;
    final normalizedSemester = semesterToId(semester) ?? semester;
    return matchingIds.contains(semesterId) ||
        matchingIds.contains(semester) ||
        matchingIds.contains(normalizedSemesterId) ||
        matchingIds.contains(normalizedSemester);
  }).toList();
}

double courseCredits(Iterable<Json> courses) => courses.fold<double>(
  0,
  (total, course) => total + (double.tryParse('${course['credit']}') ?? 0.0),
);

class SemesterChoice {
  const SemesterChoice(this.id, this.name);
  final String id, name;
}

List<SemesterChoice> semesterChoices(List<Json> raw, {bool includeAll = true}) {
  final map = <String, SemesterChoice>{};
  for (final s in raw) {
    final name = text(s, 'name'), id = semesterToId(name) ?? text(s, 'id');
    if (id.isEmpty) continue;
    final yearMatch = RegExp(
      r'(\d{4}-\d{4})',
    ).firstMatch(name.isNotEmpty ? name : id);
    final year = yearMatch != null
        ? yearMatch.group(1)!
        : (id.length >= 9 ? id.substring(0, 9) : id);
    final tabName = id.endsWith('-1')
        ? '$year秋冬'
        : id.endsWith('-2')
        ? '$year春夏'
        : semesterDisplay(id, name);
    map[id] = SemesterChoice(id, tabName);
  }
  if (map.isEmpty) {
    final current = academicSemester(beijing(DateTime.now()));
    for (
      var y = beijing(DateTime.now()).year;
      y >= beijing(DateTime.now()).year - 7;
      y--
    ) {
      map['$y-${y + 1}-1'] = SemesterChoice('$y-${y + 1}-1', '$y-${y + 1}秋冬');
      map['$y-${y + 1}-2'] = SemesterChoice('$y-${y + 1}-2', '$y-${y + 1}春夏');
    }
    map.putIfAbsent(
      current,
      () => SemesterChoice(
        current,
        current.endsWith('-1')
            ? '${current.substring(0, 9)}秋冬'
            : '${current.substring(0, 9)}春夏',
      ),
    );
  }
  final result = map.values.toList()..sort((a, b) => b.id.compareTo(a.id));
  if (includeAll) {
    result.add(const SemesterChoice('all', '全部学期（所有历史课程）'));
  }
  return result;
}

String semesterDisplay(String id, String name) {
  final yearMatch = RegExp(
    r'(\d{4}-\d{4})',
  ).firstMatch(name.isNotEmpty ? name : id);
  final year = yearMatch != null
      ? yearMatch.group(1)!
      : (id.length >= 9 ? id.substring(0, 9) : id);

  if (name.contains('秋冬')) return '$year秋冬';
  if (name.contains('春夏')) return '$year春夏';
  if (name.contains('秋')) return '$year秋';
  if (name.contains('冬')) return '$year冬';
  if (name.contains('春')) return '$year春';
  if (name.contains('夏')) return '$year夏';
  if (name.contains('短')) return '$year短';

  final normalized = semesterToId(name) ?? id;
  if (normalized.endsWith('-1')) return '$year秋冬';
  if (normalized.endsWith('-2')) return '$year春夏';
  return name.isEmpty ? normalized : name;
}

String cleanCourseExtraSuffix(String n) {
  var s = n.trim();
  s = s.replaceAll('(', '（').replaceAll(')', '）');
  String prev;
  do {
    prev = s;
    // 仅去除末尾的学期标识，例如（2024-2025-1）、（2024-2025秋冬）、（2024-2025学年秋学期）
    s = s.replaceAll(RegExp(r'（\d{4}-\d{4}[^）]*）$'), '').trim();
    // 仅去除末尾的选课代码/教学班，例如（061B0170-01）、（CS101-01）、（教学班01）、（01班）
    s = s
        .replaceAll(
          RegExp(r'（(?:[A-Za-z0-9_]+-[A-Za-z0-9_]+|教学班\d+|\d+班)）$'),
          '',
        )
        .trim();
  } while (s != prev);
  return s;
}

String normalizeCourseName(String n) {
  var s = cleanCourseExtraSuffix(n);

  // 统一括号为（）并去除多余空白
  s = s
      .replaceAll('(', '（')
      .replaceAll(')', '）')
      .replaceAll(RegExp(r'\s+'), '');

  // 1系列精确对齐为（1），绝不混淆
  s = s.replaceAll(RegExp(r'（(?:1|一|Ⅰ|I)）'), '（1）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅰ|I|1|一)$'),
    '（1）',
  );

  // 2系列精确对齐为（2），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:2|二|Ⅱ|II)[）\)]'), '（2）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅱ|II|2|二)$'),
    '（2）',
  );

  // 3系列精确对齐为（3），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:3|三|Ⅲ|III)[）\)]'), '（3）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅲ|III|3|三)$'),
    '（3）',
  );

  // 4系列精确对齐为（4），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:4|四|Ⅳ|IV)[）\)]'), '（4）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅳ|IV|4|四)$'),
    '（4）',
  );

  // 5系列精确对齐为（5），绝不混淆
  s = s.replaceAll(RegExp(r'[（\(](?:5|五|Ⅴ|V)[）\)]'), '（5）');
  s = s.replaceAll(
    RegExp(r'(?:(?<=[\u4e00-\u9fa5\）\)])|(?<=^))(?:Ⅴ|V|5|五)$'),
    '（5）',
  );

  s = s.replaceAll(RegExp(r'\s+'), '');
  return s;
}

String cleanCourseBaseName(String n) => normalizeCourseName(n);

String formatGradeBadge(String score, String gpa) {
  final s = score.trim();
  final g = double.tryParse(gpa.trim());
  final isNumScore = double.tryParse(s) != null;
  final scoreDisplay = isNumScore ? '$s分' : s;

  if (scoreDisplay.isNotEmpty && g != null && g >= 0) {
    return '$scoreDisplay / $gpa';
  } else if (scoreDisplay.isNotEmpty) {
    return scoreDisplay;
  } else if (g != null && g >= 0) {
    return '绩点 $gpa';
  }
  return '';
}
