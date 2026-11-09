/// Scenario 3: CHO setup against the real lookup endpoint.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('an unregistered phone is refused, a registered one is set up', (tester) async {
    final phone = find.byKey(const Key('setup_phone'));
    await tester.waitFor(phone);
    await tester.shot('s3_1_setup');

    await tester.enterText(phone, unregisteredPhone);
    await tester.tapOn(find.text('Continue'));
    final error = find.byKey(const Key('setup_error'));
    await tester.waitFor(error);
    final message = tester
        .widget<Text>(find.descendant(of: error, matching: find.byType(Text)))
        .data!;
    await Host.note('Unregistered phone is told: "$message"');
    expect(message, "This number isn't registered. Ask your district coordinator.");
    expect(find.byKey(const Key('home_emergency_referral')), findsNothing);
    await tester.shot('s3_2_unregistered');

    await tester.setUpCho();
    await tester.shot('s3_3_home');
    await Host.note(
      'Home shows the compound name: '
      '${find.text(compoundName).evaluate().isNotEmpty}',
    );

    await tester.tapOn(find.text('Emergency referral'));
    await tester.waitFor(find.text(compoundName), reason: 'the CHO\'s compound');
    await tester.shot('s3_4_compound');
  });
}
