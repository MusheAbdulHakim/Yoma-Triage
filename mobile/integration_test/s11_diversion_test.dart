/// Scenario 11 (batch 6): the hospital diverts the patient. The CHO's screen follows the
/// trip to the new facility and on to COMPLETED, and each party gets the right SMS.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/harness.dart';

const _secondFacility = 'Sagnarigu Polyclinic';
const _secondFacilityPhone = '+233240000201';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('a diversion changes the destination and the trip still completes', (tester) async {
    await tester.setUpCho();

    await tester.openReferralForm();
    await tester.tapOn(find.byKey(const Key('referral_skip_vitals')));
    await tester.waitFor(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), timeout: const Duration(seconds: 30));
    final dispatchId = tester.dispatchIdOnScreen();
    await Host.note('Dispatch #$dispatchId');

    final accept = await ussdAccept(motorKingDriver, dispatchId);
    expect(accept, contains('Accepted'));
    await tester.waitFor(find.byKey(const Key('dispatch_status_HOSPITAL_NOTIFIED')), timeout: const Duration(seconds: 15));
    await tester.waitFor(find.text('Going to: $facilityName'));
    await tester.shot('s11_1_accepted');

    final code = await hospitalCode(dispatchId);
    await Host.note('Hospital code: $code');

    // The driver's phone can't divert, even knowing the code.
    final refused = await hospitalReply(motorKingDriver, 'DIVERT $code $secondFacilityId');
    expect(refused['status'], 'NOT_YOUR_DISPATCH');

    expect((await hospitalReply(facilityPhone, 'CONFIRM $code'))['status'], 'CONFIRMED');
    await tester.waitFor(find.byKey(const Key('dispatch_status_HOSPITAL_CONFIRMED')), timeout: const Duration(seconds: 15));

    final diverted = await hospitalReply(facilityPhone, 'DIVERT $code $secondFacilityId');
    expect(diverted['status'], 'DIVERTED');
    await tester.waitFor(
      find.text('Going to: $_secondFacility'),
      timeout: const Duration(seconds: 15),
    );
    expect(find.text('From $facilityName, by the hospital'), findsOneWidget);
    expect(find.byKey(const Key('dispatch_status_HOSPITAL_NOTIFIED')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'still polling');
    await tester.shot('s11_2_diverted');

    final newCode = await hospitalCode(dispatchId);
    expect(newCode, isNot(code));
    expect(
      (await hospitalReply(_secondFacilityPhone, 'CONFIRM $newCode'))['status'],
      'CONFIRMED',
    );
    await tester.waitFor(find.byKey(const Key('dispatch_status_HOSPITAL_CONFIRMED')), timeout: const Duration(seconds: 15));

    final arrival = await ussdArrival(motorKingDriver);
    expect(arrival, contains('Arrival confirmed'));
    await tester.waitFor(find.byKey(const Key('dispatch_status_COMPLETED')), timeout: const Duration(seconds: 15));
    expect(find.text('Going to: $_secondFacility'), findsOneWidget);
    await tester.shot('s11_3_completed');

    // Let the sender reach everything, then check who was told what.
    await tester.wait(const Duration(seconds: 6));
    final messages = await Host.rows('outbox');
    for (final m in messages) {
      await Host.note('SMS ${m['purpose']} to ${m['recipient']}: ${m['status']}');
    }
    Set<String> to(String purpose) => messages
        .where((m) => m['purpose'] == purpose)
        .map((m) => m['recipient'] as String)
        .toSet();
    expect(to('hospital_pre_arrival'), {facilityPhone, _secondFacilityPhone});
    expect(to('divert_old_hospital'), {facilityPhone});
    expect(to('divert_driver'), {motorKingDriver});
    expect(to('divert_cho'), {registeredCho});
    expect(to('cho_driver_accepted'), {registeredCho});
    expect(to('cho_arrival'), {registeredCho});
    expect(to('hospital_arrival'), {_secondFacilityPhone});
    expect(
      messages.where((m) => m['status'] == 'FAILED'),
      isEmpty,
      reason: 'mock SMS: nothing should fail',
    );

    final dispatch =
        (await Host.rows('dispatches')).singleWhere((d) => d['id'] == dispatchId);
    expect(dispatch['status'], 'COMPLETED');
    expect(dispatch['facility_id'], secondFacilityId);
    final driver = (await Host.rows('drivers')).singleWhere((d) => d['phone'] == motorKingDriver);
    expect(driver['availability'], 'AVAILABLE', reason: 'the trip is over');
  });
}
