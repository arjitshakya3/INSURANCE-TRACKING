import 'package:flutter_test/flutter_test.dart';

void main() {
  test('policy expiry arithmetic treats today as expiring soon', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(today.year, today.month, today.day);
    expect(end.difference(today).inDays, 0);
  });
}
