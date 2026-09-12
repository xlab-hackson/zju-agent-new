import 'models.dart';

int? deadlineMs(Json a) {
  final raw = text(a, 'deadline');
  final date = DateTime.tryParse(raw);
  return date?.millisecondsSinceEpoch;
}

const oneWeekMs = 7 * 24 * 3600 * 1000;

bool isVisibleAssignment(Json a, int nowMs) {
  final due = deadlineMs(a);
  if (due == null) return true;
  if (due > nowMs) return true;
  return nowMs - due <= oneWeekMs;
}

int? examMs(Json a) {
  final date = DateTime.tryParse(text(a, 'time'));
  return date?.millisecondsSinceEpoch;
}

bool isSubmitted(Json a) => a['submitted'] == true;

int compareAssignments(Json a, Json b) {
  final subA = isSubmitted(a), subB = isSubmitted(b);
  if (subA != subB) return subA ? 1 : -1;
  final da = deadlineMs(a), db = deadlineMs(b);
  if (da == null && db == null) return 0;
  if (da == null) return 1;
  if (db == null) return -1;
  return da.compareTo(db);
}
