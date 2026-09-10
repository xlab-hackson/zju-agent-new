typedef Json = Map<String, dynamic>;

class AppError implements Exception {
  const AppError(this.code, this.message, {this.retryable = false});
  final String code;
  final String message;
  final bool retryable;
  @override
  String toString() => message;
}

Json object(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const AppError('ZJU_RESPONSE_PARSE_FAILED', '响应格式异常，请重试。');
}

List<Json> rows(Object? value) {
  if (value is! List) {
    throw const AppError('ZJU_RESPONSE_PARSE_FAILED', '响应缺少列表数据。');
  }
  return value.map(object).toList();
}

String text(Json value, String key, [String fallback = '']) =>
    value[key]?.toString() ?? fallback;
int integer(Object? value, [int fallback = 0]) =>
    int.tryParse('$value') ?? fallback;

class AgentEvent {
  const AgentEvent(this.type, [this.data = const {}]);
  final String type;
  final Json data;
  Json toJson() => {'type': type, ...data};
}

class TimetableEntry {
  const TimetableEntry({
    required this.id,
    required this.courseName,
    required this.weekday,
    required this.startSection,
    required this.endSection,
    this.teacher = '',
    this.location = '',
    this.semester = '',
    this.subSemester = '',
    this.weeks = const [],
  });
  final String id, courseName, teacher, location, semester, subSemester;
  final int weekday, startSection, endSection;
  final List<int> weeks;
  factory TimetableEntry.fromJson(Json j) => TimetableEntry(
    id: text(j, 'id'),
    courseName: text(j, 'courseName'),
    weekday: integer(j['weekday']),
    startSection: integer(j['startSection']),
    endSection: integer(j['endSection']),
    teacher: text(j, 'teacher'),
    location: text(j, 'location'),
    semester: text(j, 'semester'),
    subSemester: text(j, 'subSemester'),
    weeks: (j['weeks'] as List? ?? []).map((e) => integer(e)).toList(),
  );
  Json toJson() => {
    'id': id,
    'courseName': courseName,
    'weekday': weekday,
    'startSection': startSection,
    'endSection': endSection,
    'teacher': teacher,
    'location': location,
    'semester': semester,
    'subSemester': subSemester,
    'weeks': weeks,
  };
}

int timetableCourseCount(Iterable<TimetableEntry> entries) => entries
    .map((entry) => entry.courseName.trim())
    .where((name) => name.isNotEmpty)
    .toSet()
    .length;

List<TimetableEntry> mergeTimetable(List<TimetableEntry> entries) {
  final sorted = [...entries]
    ..sort((a, b) => a.startSection.compareTo(b.startSection));
  final result = <TimetableEntry>[];
  for (final e in sorted) {
    final i = result.indexWhere(
      (p) =>
          p.courseName == e.courseName &&
          p.teacher == e.teacher &&
          p.location == e.location &&
          p.weekday == e.weekday &&
          p.semester == e.semester &&
          p.subSemester == e.subSemester &&
          p.weeks.join(',') == e.weeks.join(',') &&
          e.startSection <= p.endSection + 1,
    );
    if (i < 0) {
      result.add(e);
    } else {
      final p = result[i];
      result[i] = TimetableEntry.fromJson({
        ...p.toJson(),
        'endSection': e.endSection > p.endSection ? e.endSection : p.endSection,
      });
    }
  }
  return result..sort(
    (a, b) => a.weekday != b.weekday
        ? a.weekday.compareTo(b.weekday)
        : a.startSection.compareTo(b.startSection),
  );
}
