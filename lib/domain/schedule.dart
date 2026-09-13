import 'models.dart';

const sessionTimes = [
  ['00:00', '00:00'],
  ['08:00', '08:45'],
  ['08:50', '09:35'],
  ['10:00', '10:45'],
  ['10:50', '11:35'],
  ['11:40', '12:25'],
  ['13:25', '14:10'],
  ['14:15', '15:00'],
  ['15:05', '15:50'],
  ['16:15', '17:00'],
  ['17:05', '17:50'],
  ['18:50', '19:35'],
  ['19:40', '20:25'],
  ['20:30', '21:15'],
  ['21:20', '22:05'],
  ['22:10', '22:55'],
];
// Calendar arithmetic uses UTC objects as wall-clock dates in Asia/Shanghai.
DateTime beijing(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));
DateTime day(DateTime wall) => DateTime.utc(wall.year, wall.month, wall.day);
String isoDay(DateTime d) => d.toIso8601String().substring(0, 10);
String compact(DateTime d) => isoDay(d).replaceAll('-', '');
DateTime parseDay(String d) => DateTime.utc(
  int.parse(d.substring(0, 4)),
  int.parse(d.substring(4, 6)),
  int.parse(d.substring(6, 8)),
);
String academicSemester(DateTime wall) {
  final y = wall.year;
  if (wall.month == 1 && wall.day <= 25) return '${y - 1}-$y-1';
  if (wall.month <= 6 || (wall.month == 7 && wall.day <= 10)) {
    return '${y - 1}-$y-2';
  }
  return '$y-${y + 1}-1';
}

String? semesterToId(String name) {
  final trimmed = name.trim();
  if (RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(trimmed)) {
    return trimmed;
  }
  final m = RegExp(r'(\d{4}-\d{4})').firstMatch(trimmed);
  if (m == null) return null;
  final year = m.group(1)!;
  if (trimmed.contains('春') || trimmed.contains('夏') || trimmed.endsWith('-2')) {
    return '$year-2';
  }
  if (trimmed.contains('秋') || trimmed.contains('冬') || trimmed.contains('短') || trimmed.endsWith('-1')) {
    return '$year-1';
  }
  return null;
}

Json dateInfo(DateTime wall, Json config) {
  final target = day(wall), key = compact(wall);
  final bounds = (config['startEnd'] as List)
      .map((e) => parseDay('$e'))
      .toList();
  final autumn = text(config, 'semesterId').endsWith('-1');
  var type = 'instruction', sub = '', label = '', week = 0;
  if (target.isBefore(bounds[0])) {
    type = 'preparation';
    label = '开学准备';
  } else if (!target.isAfter(bounds[1])) {
    sub = autumn ? '秋' : '春';
    week = target.difference(bounds[0]).inDays ~/ 7 + 1;
  } else if (target.isBefore(bounds[2])) {
    sub = autumn ? '秋' : '春';
    week = 8;
  } else if (!target.isAfter(bounds[3])) {
    sub = autumn ? '冬' : '夏';
    week = target.difference(bounds[2]).inDays ~/ 7 + 9;
  } else {
    type = target.difference(bounds[3]).inDays <= 14 ? 'exam' : 'break';
    label = type == 'exam' ? '期末考试周' : '假期';
  }
  if (week > 0) label = '$sub第${week > 8 ? week - 8 : week}周';
  final holidays = object(config['holiday'] ?? {}),
      exchanges = object(config['exchange'] ?? {});
  var holiday = holidays.containsKey(key),
      makeup = false,
      weekday = target.weekday;
  String? makeupDate;
  for (final pair in exchanges.keys.where((k) => k.length == 16)) {
    if (pair.substring(0, 8) == key) holiday = true;
    if (pair.substring(8) == key) {
      makeup = true;
      final original = parseDay(pair.substring(0, 8));
      weekday = original.weekday;
      makeupDate = isoDay(original);
    }
  }
  return {
    'date': isoDay(target),
    'semesterId': config['semesterId'],
    'periodType': type,
    'subTerm': sub,
    'week': week,
    'weekString': label,
    'weekday': target.weekday,
    'effectiveWeekday': holiday && !makeup ? 0 : weekday,
    'isHoliday': holiday,
    'isMakeupDay': makeup,
    'makeupTargetDate': makeupDate,
  };
}

List<Json> dailyEvents(
  DateTime wall,
  Json config,
  List<TimetableEntry> timetable,
  List<Json> exams,
  List<Json> assignments,
) {
  final info = dateInfo(wall, config), date = isoDay(wall);
  final projection = info['makeupTargetDate'] != null
      ? dateInfo(
          DateTime.parse('${info['makeupTargetDate']}T00:00:00Z'),
          config,
        )
      : info;
  final result = <Json>[];
  if (info['effectiveWeekday'] != 0 &&
      projection['periodType'] == 'instruction') {
    for (final e in timetable) {
      if (!e.selected) continue;
      final w = integer(projection['week']);
      if (e.weekday != info['effectiveWeekday'] ||
          (e.weeks.isNotEmpty && !e.weeks.contains(w))) {
        continue;
      }
      if (e.subSemester.isNotEmpty &&
          !e.subSemester.contains('${projection['subTerm']}')) {
        continue;
      }
      if (e.startSection < 1 || e.endSection >= sessionTimes.length) continue;
      result.add({
        ...e.toJson(),
        'type': 'class',
        'title': e.courseName,
        'date': date,
        'startTime': sessionTimes[e.startSection][0],
        'endTime': sessionTimes[e.endSection][1],
      });
    }
  }
  for (final record in [
    ...exams.map((e) => {...e, 'type': 'exam'}),
    ...assignments
        .where((a) => a['submitted'] != true)
        .map((a) => {...a, 'type': 'assignment'}),
  ]) {
    final raw = text(record, record['type'] == 'exam' ? 'time' : 'deadline');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) continue;
    final time = beijing(parsed);
    if (isoDay(time) != date) continue;
    final hm = time.toIso8601String().substring(11, 16);
    result.add({
      ...record,
      'title': record['title'] ?? record['courseName'],
      'date': date,
      'startTime': hm,
      'endTime': hm,
    });
  }
  result.sort((a, b) => text(a, 'startTime').compareTo(text(b, 'startTime')));
  return result;
}
