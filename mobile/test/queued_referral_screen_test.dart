import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';

void main() {
  testWidgets('shows honest queued state without a driver assignment',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: QueuedReferralScreen(clientRequestId: 'request-123'),
      ),
    );

    expect(
      find.text(
        'Referral saved on this device. Drivers have not been notified yet. '
        'They will be contacted when this phone has coverage.',
      ),
      findsOneWidget,
    );
    // The raw request id is a debug detail, shown only in test builds.
    expect(find.textContaining('Request:'), findsNothing);
    expect(find.textContaining('request-123'), findsNothing);
    expect(find.text('Retry sync'), findsOneWidget);
    expect(find.textContaining('Driver:'), findsNothing);
  });
}
