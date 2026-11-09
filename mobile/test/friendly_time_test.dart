import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/friendly_time.dart';

void main() {
  test('ages read naturally, with correct plurals', () {
    expect(ago(const Duration(seconds: 10)), 'just now');
    expect(ago(const Duration(seconds: 61)), '1 minute ago');
    expect(ago(const Duration(minutes: 5)), '5 minutes ago');
    expect(ago(const Duration(hours: 1, minutes: 3)), '1 hour ago');
    expect(ago(const Duration(days: 2)), '2 days ago');
    expect(countOf(1, 'minute'), '1 minute');
    expect(countOf(3, 'referral'), '3 referrals');
  });

  testWidgets('Today / Yesterday / date, in the phone\'s clock format', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    final now = DateTime(2026, 11, 9, 18, 0);
    expect(friendlyWhen(ctx, DateTime(2026, 11, 9, 17, 43), now: now), 'Today, 17:43');
    expect(friendlyWhen(ctx, DateTime(2026, 11, 8, 9, 12), now: now), 'Yesterday, 09:12');
    expect(friendlyWhen(ctx, DateTime(2026, 11, 5, 9, 12), now: now), '5 Nov, 09:12');
    expect(shortWhen(ctx, DateTime(2026, 11, 9, 7, 5), now: now), '07:05');
    expect(friendlyWhen(ctx, DateTime(2026, 11, 9, 17, 43), now: now), isNot(contains('2026-')));
  });
}
