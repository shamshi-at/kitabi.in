import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/lending/reminder.dart';

void main() {
  test('reminderIdForRecord is stable and non-negative', () {
    const id = 'a1b2c3d4-0000-0000-0000-000000000000';
    expect(reminderIdForRecord(id), reminderIdForRecord(id));
    expect(reminderIdForRecord(id), greaterThanOrEqualTo(0));
    expect(reminderIdForRecord('other-id'), isNot(reminderIdForRecord(id)));
  });

  test('reminderTimeFor fires at 9am local on the due date', () {
    final when = reminderTimeFor(DateTime(2026, 7, 20));
    expect(when, DateTime(2026, 7, 20, 9));
  });
}
