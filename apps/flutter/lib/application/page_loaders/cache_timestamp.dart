import '../services.dart';

Future<String?> pageUpdatedAt(
  AppServices s, {
  Iterable<String> cacheKeys = const [],
  Iterable<String> cachePrefixes = const [],
  Iterable<String> calendarKeys = const [],
}) async {
  final time = await s.campus.oldestUpdatedAt(
    cacheKeys: cacheKeys,
    cachePrefixes: cachePrefixes,
    calendarKeys: calendarKeys,
  );
  return time?.toIso8601String();
}
