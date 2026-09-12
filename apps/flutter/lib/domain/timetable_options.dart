import 'models.dart';

const dayNames = ['一', '二', '三', '四', '五', '六', '日'];
String weekdayName(int day) =>
    (day >= 1 && day <= 7) ? dayNames[day - 1] : '$day';

class SubSemesterChoice {
  const SubSemesterChoice({required this.id, required this.name});
  final String id;
  final String name;
}

List<SubSemesterChoice> getSubSemesterChoices(
  String semester, [
  Iterable<TimetableEntry> entries = const [],
]) {
  final s = semester.toLowerCase();
  if (s.contains('秋冬') ||
      s.endsWith('-1') ||
      s.contains('秋') ||
      s.contains('冬')) {
    return const [
      SubSemesterChoice(id: '秋', name: '秋学期'),
      SubSemesterChoice(id: '冬', name: '冬学期'),
    ];
  }
  if (s.contains('春夏') ||
      s.endsWith('-2') ||
      s.contains('春') ||
      s.contains('夏')) {
    return const [
      SubSemesterChoice(id: '春', name: '春学期'),
      SubSemesterChoice(id: '夏', name: '夏学期'),
    ];
  }
  if (s.contains('暑') || s.contains('短') || s.endsWith('-3')) {
    return const [SubSemesterChoice(id: '暑', name: '暑学期')];
  }
  final subs = entries
      .map((e) => e.subSemester.trim())
      .where((sub) => sub.isNotEmpty)
      .toSet();
  if (subs.isNotEmpty) {
    return [for (final sub in subs) SubSemesterChoice(id: sub, name: '$sub学期')];
  }
  return const [];
}

List<TimetableEntry> filterTimetableBySubSemester(
  List<TimetableEntry> entries,
  String subSemester,
) {
  if (subSemester.isEmpty) {
    return entries;
  }
  return entries.where((e) {
    if (e.subSemester.isEmpty) return true;
    return e.subSemester.contains(subSemester);
  }).toList();
}

String compressWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = [...weeks]..sort();
  final parts = <String>[];
  var start = sorted.first, end = sorted.first;
  for (final week in sorted.skip(1)) {
    if (week == end + 1) {
      end = week;
    } else {
      parts.add(start == end ? '$start' : '$start-$end');
      start = end = week;
    }
  }
  parts.add(start == end ? '$start' : '$start-$end');
  return parts.join(',');
}
