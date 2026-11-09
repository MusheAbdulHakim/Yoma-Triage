// BUG-5: a diversion changes where the patient is going. The status screen keeps
// following the trip and shows the new destination.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/services/api_client.dart';

import 'helpers/vitals_helper.dart';

class _Trip extends ApiClient {
  _Trip(this.replies);

  final List<Map<String, dynamic>> replies;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async {
    final reply = replies[calls < replies.length ? calls : replies.length - 1];
    calls++;
    return {'id': id, 'current_tier': 1, 'driver_name': 'Ibrahim', ...reply};
  }
}

const _toFirst = {
  'status': 'HOSPITAL_NOTIFIED',
  'facility_id': 1,
  'facility_name': 'Tamale Teaching Hospital',
  'diverted_from': null,
};
const _toSecond = {
  'status': 'HOSPITAL_NOTIFIED',
  'facility_id': 2,
  'facility_name': 'Navrongo War Memorial Hospital',
  'diverted_from': 'Tamale Teaching Hospital',
};

Future<void> _open(WidgetTester tester, ApiClient api) async {
  useTallScreen(tester);
  await tester.pumpWidget(
    MaterialApp(home: DispatchStatusScreen(dispatchId: 5, clientRequestId: 'r', api: api)),
  );
  await tester.pump();
  await tester.pump();
}

/// One poll interval of the screen, which checks every 2 s while things are fine.
Future<void> _nextPoll(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}

void main() {
  testWidgets('after a diversion it shows the new destination and keeps checking',
      (tester) async {
    final api = _Trip([_toFirst, _toSecond, {..._toSecond, 'status': 'COMPLETED'}]);
    await _open(tester, api);
    expect(find.text('Going to: Tamale Teaching Hospital'), findsOneWidget);
    expect(find.byKey(const Key('dispatch_diverted')), findsNothing);

    await _nextPoll(tester);
    expect(find.text('Going to: Navrongo War Memorial Hospital'), findsOneWidget);
    expect(
      find.text('From Tamale Teaching Hospital, by the hospital'),
      findsOneWidget,
    );
    expect(api.calls, 2, reason: 'still live: it keeps checking after the diversion');

    await _nextPoll(tester);
    expect(find.byKey(const Key('dispatch_status_COMPLETED')), findsOneWidget);
    final callsAtEnd = api.calls;
    await _nextPoll(tester);
    expect(api.calls, callsAtEnd, reason: 'COMPLETED is the end; polling stops');
  });

  testWidgets('Going to sits under the title and follows the diversion; Back to Home is quiet',
      (tester) async {
    final api = _Trip([_toFirst, _toSecond]);
    await _open(tester, api);
    Finder inAppBar(String text) =>
        find.descendant(of: find.byType(AppBar), matching: find.text(text));
    expect(inAppBar('Going to: Tamale Teaching Hospital'), findsOneWidget);

    await _nextPoll(tester);
    expect(inAppBar('Going to: Navrongo War Memorial Hospital'), findsOneWidget);
    expect(find.text('Going to: Tamale Teaching Hospital'), findsNothing);

    final back = find.byKey(const Key('dispatch_back_home'));
    expect(tester.widget(back), isA<TextButton>(), reason: 'a quiet text button');
    expect(find.widgetWithText(OutlinedButton, 'Back to Home'), findsNothing);
    // At the bottom: below Cancel referral.
    expect(tester.getRect(back).top,
        greaterThanOrEqualTo(tester.getRect(find.byKey(const Key('dispatch_cancel'))).bottom));
  });

  testWidgets('a DIVERTED status from an older server is not treated as the end',
      (tester) async {
    final api = _Trip([
      {..._toSecond, 'status': 'DIVERTED'},
      {..._toSecond, 'status': 'COMPLETED'},
    ]);
    await _open(tester, api);
    expect(find.byKey(const Key('dispatch_status_DIVERTED')), findsOneWidget);

    await _nextPoll(tester);
    expect(api.calls, 2, reason: 'it polled again after DIVERTED');
    expect(find.byKey(const Key('dispatch_status_COMPLETED')), findsOneWidget);
  });

  testWidgets('a server without the new fields still shows the status', (tester) async {
    final api = _Trip([
      {'status': 'HOSPITAL_NOTIFIED', 'facility_id': 1},
    ]);
    await _open(tester, api);
    expect(find.byKey(const Key('dispatch_status_HOSPITAL_NOTIFIED')), findsOneWidget);
    expect(find.byKey(const Key('dispatch_destination')), findsNothing);
    expect(find.byKey(const Key('dispatch_diverted')), findsNothing);
  });
}
