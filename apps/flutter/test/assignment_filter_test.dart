import 'package:flutter_test/flutter_test.dart';
import 'package:zju_campus_agent/ui/pages_v2.dart';

void main() {
  test('isVisibleAssignment logic matches 1-week overdue threshold', () {
    final now = DateTime(2026, 9, 12, 12, 0);
    final nowMs = now.millisecondsSinceEpoch;

    // 1. No deadline -> visible
    expect(isVisibleAssignment({'title': '无截止时间'}, nowMs), isTrue);

    // 2. Future deadline (not due yet) -> visible
    final future = now.add(const Duration(days: 3)).toIso8601String();
    expect(isVisibleAssignment({'deadline': future}, nowMs), isTrue);

    // 3. Past deadline but within 7 days -> visible
    final past3Days = now.subtract(const Duration(days: 3)).toIso8601String();
    expect(isVisibleAssignment({'deadline': past3Days}, nowMs), isTrue);

    final past6Days = now.subtract(const Duration(days: 6, hours: 23)).toIso8601String();
    expect(isVisibleAssignment({'deadline': past6Days}, nowMs), isTrue);

    // 4. Past deadline over 7 days -> hidden
    final past8Days = now.subtract(const Duration(days: 8)).toIso8601String();
    expect(isVisibleAssignment({'deadline': past8Days}, nowMs), isFalse);

    final past30Days = now.subtract(const Duration(days: 30)).toIso8601String();
    expect(isVisibleAssignment({'deadline': past30Days}, nowMs), isFalse);
  });

  test('compareAssignments sorts unsubmitted before submitted, and sorts by deadline', () {
    final a1 = {'id': '1', 'title': '急', 'deadline': '2026-09-15T12:00:00', 'submitted': false};
    final a2 = {'id': '2', 'title': '更晚', 'deadline': '2026-09-20T12:00:00', 'submitted': false};
    final a3 = {'id': '3', 'title': '无时间', 'submitted': false};
    final a4 = {'id': '4', 'title': '已交早', 'deadline': '2026-09-10T12:00:00', 'submitted': true};
    final a5 = {'id': '5', 'title': '已交晚', 'deadline': '2026-09-25T12:00:00', 'submitted': true};

    final list = [a5, a2, a4, a3, a1];
    list.sort(compareAssignments);

    expect(list.map((a) => a['id']).toList(), ['1', '2', '3', '4', '5']);
  });
}
