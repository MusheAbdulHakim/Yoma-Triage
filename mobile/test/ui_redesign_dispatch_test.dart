// UI redesign round 3: the dispatch status timeline. The polling, cancel and manual
// fallback are unchanged; these tests pin what the screen shows for each status.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/contacts_store.dart';
import 'package:yoma_triage/services/dispatch_timeline.dart';
import 'package:yoma_triage/services/friendly_time.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'helpers/cho_helper.dart';

/// Answers each poll with the next scripted dispatch; the last one repeats.
class _ScriptedApi extends ApiClient {
  _ScriptedApi(this.responses);

  final List<Map<String, dynamic>> responses;
  int polls = 0;

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async {
    final r = responses[polls < responses.length ? polls : responses.length - 1];
    polls++;
    return r;
  }

  int cancels = 0;

  @override
  Future<Map<String, dynamic>> cancelDispatch({
    required int dispatchId,
    required String choPhone,
  }) async {
    cancels++;
    return {'status': 'CANCELLED'};
  }
}

Map<String, dynamic> _dispatch(
  String status, {
  String? driver,
  String? divertedFrom,
  String facility = 'Tamale Teaching Hospital',
}) =>
    {
      'id': 9,
      'referral_id': 4821,
      'facility_id': 1,
      'facility_name': facility,
      'diverted_from': divertedFrom,
      'driver_id': driver == null ? null : 3,
      'driver_name': driver,
      'eta_minutes': driver == null ? null : 12,
      'status': status,
      'current_tier': 1,
      // Never shown to the CHO, even if a server ever sent it.
      'hospital_code': '7391',
      'step_times': {
        'sent': '2026-11-09T09:12:00+00:00',
        'drivers_notified': '2026-11-09T09:13:00+00:00',
        'driver_accepted': driver == null ? null : '2026-11-09T09:17:00+00:00',
        'hospital_notified': null,
        'hospital_confirmed': null,
        'diverted': null,
        'completed': null,
      },
    };

Map<String, Object> _contactsPrefs({int drivers = 2}) => {
      ...registeredChoPrefs(),
      ContactsStore.prefsKey: jsonEncode({
        'compound_id': 1,
        'drivers': [
          for (var i = 0; i < drivers; i++)
            {'name': 'Driver ${i + 1}', 'phone': '+23324000${1000 + i}', 'is_motor_king': i == 0},
        ],
        'facilities': [
          {'id': 1, 'name': 'Tamale Teaching Hospital', 'phone': '+233240000200'},
        ],
      }),
      ContactsStore.updatedAtPrefsKey: DateTime.utc(2026, 11, 5, 8, 30).toIso8601String(),
    };

Future<_ScriptedApi> _open(
  WidgetTester tester,
  List<Map<String, dynamic>> responses, {
  double textScale = 1.0,
}) async {
  final api = _ScriptedApi(responses);
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: DispatchStatusScreen(
      dispatchId: 9,
      clientRequestId: 'req-1',
      facilityId: 1,
      api: api,
      launcher: (_) async => true,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return api;
}

/// The waiting screen has a spinner, so pumpAndSettle would never return.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

TimelineStep _step(DispatchTimeline t, String id) => t.steps.firstWhere((s) => s.id == id);

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(_contactsPrefs()));

  group('timeline wording', () {
    const pastTense = ['Driver accepted', 'Hospital confirmed', 'Arrived', 'Diverted'];

    test('every status: at most one current step, and past tense only for done steps', () {
      for (final status in [
        'PENDING',
        'TIER1_NOTIFIED',
        'TIER2_NOTIFIED',
        'ACCEPTED',
        'HOSPITAL_NOTIFIED',
        'HOSPITAL_CONFIRMED',
        'DIVERTED',
        'COMPLETED',
        'FAILED',
        'CANCELLED',
        'SOMETHING_NEW',
      ]) {
        final t = dispatchTimeline(status: status, driverName: 'Ibrahim');
        expect(t.steps.where((s) => s.state == TimelineState.current).length, lessThanOrEqualTo(1),
            reason: status);
        for (final step in t.steps) {
          if (pastTense.contains(step.label)) {
            expect(step.state, TimelineState.done, reason: '$status: ${step.label}');
          }
        }
      }
    });

    test('waiting for drivers', () {
      final t = dispatchTimeline(status: 'TIER1_NOTIFIED');
      expect(t.current!.label, 'Waiting for a driver to accept');
      expect(_step(t, 'drivers').state, TimelineState.done);
      expect(_step(t, 'hospital').label, 'Hospital confirms');
      expect(t.waitingForDriver, isTrue);
      expect(dispatchTimeline(status: 'PENDING').current!.label, 'Notifying drivers');
    });

    test('driver accepted: name shown, hospital is in progress', () {
      final t = dispatchTimeline(status: 'HOSPITAL_NOTIFIED', driverName: 'Ibrahim');
      expect(_step(t, 'driver').label, 'Driver accepted');
      expect(_step(t, 'driver').detail, 'Ibrahim');
      expect(t.current!.label, 'Waiting for hospital to confirm');
      expect(t.waitingForDriver, isFalse);
    });

    test('hospital confirmed: on the way to the destination', () {
      final t = dispatchTimeline(
          status: 'HOSPITAL_CONFIRMED', driverName: 'Ibrahim', facilityName: 'Tamale');
      expect(_step(t, 'hospital').label, 'Hospital confirmed');
      expect(t.current!.label, 'On the way to Tamale');
    });

    test('completed: Arrived, and "Hospital confirmed" only if it was seen', () {
      final t = dispatchTimeline(status: 'COMPLETED', driverName: 'Ibrahim');
      expect(_step(t, 'trip').label, 'Arrived');
      expect(_step(t, 'hospital').label, 'Hospital notified');
      expect(t.current, isNull);
      final seen = dispatchTimeline(status: 'COMPLETED', sawConfirmed: true);
      expect(_step(seen, 'hospital').label, 'Hospital confirmed');
    });

    test('no driver: help card, no past tense for the driver', () {
      final t = dispatchTimeline(status: 'FAILED');
      expect(t.help, DispatchHelp.noDriver);
      expect(t.current!.label, 'No driver has accepted');
    });

    test('diverted: a done step with a teal note naming the new facility', () {
      final t = dispatchTimeline(
        status: 'HOSPITAL_NOTIFIED',
        driverName: 'Ibrahim',
        facilityName: 'Navrongo',
        divertedFrom: 'Tamale',
      );
      final d = _step(t, 'diverted');
      expect(d.state, TimelineState.done);
      expect(d.note, 'Now going to Navrongo');
      expect(t.steps.indexOf(d), lessThan(t.steps.indexOf(_step(t, 'hospital'))));
    });

    test('late acceptance is shown as accepted, with a note', () {
      final t =
          dispatchTimeline(status: 'HOSPITAL_NOTIFIED', driverName: 'Ibrahim', acceptedLate: true);
      expect(_step(t, 'driver').label, 'Driver accepted');
      expect(_step(t, 'driver').detail, 'Ibrahim · Accepted after the alerts had stopped');
    });

    test('not sent yet', () {
      final t = queuedTimeline();
      expect(t.current!.label, 'Saved on this phone – will send when signal returns');
      expect(t.help, DispatchHelp.notSentYet);
      expect(t.steps.where((s) => s.state == TimelineState.done), isEmpty);
    });

    test('each step reads as one sentence for screen readers', () {
      final t = dispatchTimeline(status: 'HOSPITAL_NOTIFIED', driverName: 'Ibrahim');
      expect(_step(t, 'driver').spoken, 'Done: Driver accepted, Ibrahim');
      expect(t.current!.spoken, 'Now: Waiting for hospital to confirm');
    });
  });

  group('screen per status', () {
    testWidgets('in progress: waiting label, Ref, Call a driver instead, Cancel referral',
        (tester) async {
      await _open(tester, [_dispatch('TIER1_NOTIFIED')]);
      expect(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), findsOneWidget);
      expect(find.text('Waiting for a driver to accept'), findsOneWidget);
      expect(find.text('Ref 4821'), findsOneWidget);
      expect(find.byKey(const Key('manual_contacts')), findsNothing);

      await tester.tap(find.byKey(const Key('dispatch_call_instead')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('manual_contacts'), skipOffstage: false), findsOneWidget);

      final cancel = find.byKey(const Key('dispatch_cancel'));
      await tester.scrollUntilVisible(cancel, 200,
          scrollable: find.descendant(
              of: find.byKey(const Key('dispatch_scroll')), matching: find.byType(Scrollable)));
      expect(find.text('Cancel referral'), findsOneWidget);
      expect(tester.getSize(cancel).height, greaterThanOrEqualTo(48));
      // Same confirmation as before.
      await tester.tap(cancel);
      await tester.pump();
      expect(find.text('Cancel this dispatch?'), findsOneWidget);
      expect(find.text('Keep it'), findsOneWidget);
    });

    testWidgets('driver accepted: name, and the hospital step in progress', (tester) async {
      await _open(tester, [_dispatch('HOSPITAL_NOTIFIED', driver: 'Ibrahim')]);
      expect(find.byKey(const Key('timeline_driver_done')), findsOneWidget);
      expect(find.text('Ibrahim'), findsOneWidget);
      expect(find.text('Waiting for hospital to confirm'), findsOneWidget);
      expect(find.byKey(const Key('dispatch_call_instead')), findsNothing);
      // No ETA.
      expect(find.textContaining('ETA'), findsNothing);
      expect(find.textContaining('12m'), findsNothing);
    });

    testWidgets('no driver: navy card and Call/SMS rows', (tester) async {
      await _open(tester, [_dispatch('FAILED')]);
      expect(find.text('No driver has accepted. Call one now.'), findsOneWidget);
      final card = tester.widget<Container>(find
          .descendant(of: find.byKey(const Key('dispatch_help')), matching: find.byType(Container))
          .first);
      expect((card.decoration! as BoxDecoration).color, YomaColors.navy);
      expect(find.byKey(const Key('manual_contacts'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('diverted: done step and the teal note', (tester) async {
      await _open(tester, [
        _dispatch('HOSPITAL_NOTIFIED',
            driver: 'Ibrahim',
            facility: 'Navrongo Hospital',
            divertedFrom: 'Tamale Teaching Hospital'),
      ]);
      expect(find.byKey(const Key('timeline_diverted_done')), findsOneWidget);
      expect(find.text('Now going to Navrongo Hospital'), findsOneWidget);
      final note = tester.widget<Container>(find.byKey(const Key('timeline_note')));
      expect((note.decoration! as BoxDecoration).color, YomaColors.brandTint);
    });

    Map<String, dynamic> lateWindow(Map<String, dynamic> d, Duration fromNow) => {
          ...d,
          'late_claim_until': DateTime.now().toUtc().add(fromNow).toIso8601String(),
        };

    testWidgets('after FAILED it keeps checking every 30 s and shows a late acceptance',
        (tester) async {
      final api = await _open(tester, [
        lateWindow(_dispatch('FAILED'), const Duration(minutes: 40)),
        lateWindow(_dispatch('FAILED'), const Duration(minutes: 40)),
        lateWindow(_dispatch('HOSPITAL_NOTIFIED', driver: 'Ibrahim'), const Duration(minutes: 40)),
      ]);
      expect(find.byKey(const Key('dispatch_status_FAILED')), findsOneWidget);
      expect(find.byKey(const Key('dispatch_late_claim_watch')), findsOneWidget);
      final afterFirst = api.polls;

      // Not the 2 s of an active dispatch: nothing new before 30 s.
      await tester.pump(const Duration(seconds: 29));
      expect(api.polls, afterFirst);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.polls, afterFirst + 1);
      expect(find.byKey(const Key('dispatch_status_FAILED')), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.byKey(const Key('dispatch_status_HOSPITAL_NOTIFIED')), findsOneWidget);
      expect(find.textContaining('Accepted after the alerts had stopped'), findsOneWidget);
      expect(find.byKey(const Key('dispatch_late_claim_watch')), findsNothing);
    });

    testWidgets('once the late-claim window has ended, FAILED stops checking', (tester) async {
      final api = await _open(tester, [
        lateWindow(_dispatch('FAILED'), const Duration(minutes: -1)),
        lateWindow(_dispatch('HOSPITAL_NOTIFIED', driver: 'Ibrahim'), const Duration(minutes: -1)),
      ]);
      final polls = api.polls;
      await tester.pump(const Duration(minutes: 2));
      expect(api.polls, polls);
      expect(find.byKey(const Key('dispatch_late_claim_watch')), findsNothing);
    });

    testWidgets('the hospital code never appears', (tester) async {
      for (final status in [
        'TIER1_NOTIFIED',
        'HOSPITAL_NOTIFIED',
        'HOSPITAL_CONFIRMED',
        'FAILED'
      ]) {
        await tester.pumpWidget(const SizedBox());
        await _open(tester, [_dispatch(status, driver: 'Ibrahim')]);
        expect(find.textContaining('7391', skipOffstage: false), findsNothing, reason: status);
      }
    });

    testWidgets('not sent yet: saved step and the navy "Urgent?" card', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildYomaTheme(),
        home: QueuedReferralScreen(
            clientRequestId: 'req-1', facilityId: 1, launcher: (_) async => true),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Saved on this phone – will send when signal returns'), findsOneWidget);
      expect(find.textContaining('Drivers have not been notified'), findsOneWidget);
      expect(find.text('Urgent? Call a driver now', skipOffstage: false), findsOneWidget);
    });
  });

  group('Call a driver instead, then "Did a driver agree to come?"', () {
    Future<_ScriptedApi> callADriver(WidgetTester tester, {String status = 'TIER1_NOTIFIED'}) async {
      SharedPreferences.setMockInitialValues({
        ..._contactsPrefs(drivers: 2),
        ...registeredChoPrefs(),
      });
      _screen(tester, const Size(360, 1200));
      final api = await _open(tester, [_dispatch(status)]);
      await tester.tap(find.text('Call a driver instead'));
      await _settle(tester);
      // No confirm: the call starts straight away.
      await tester.tap(find.byKey(const Key('call_+233240001000')));
      await _settle(tester);
      expect(find.byKey(const Key('dispatch_driver_agreed')), findsNothing,
          reason: 'asked only when the CHO comes back');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      return api;
    }

    testWidgets('Yes cancels the referral through the normal cancel', (tester) async {
      final api = await callADriver(tester);
      expect(find.text('Did a driver agree to come?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dispatch_driver_agreed_yes')));
      await _settle(tester);
      expect(api.cancels, 1);
      expect(find.byKey(const Key('dispatch_status_CANCELLED')), findsOneWidget);
    });

    testWidgets('No keeps waiting', (tester) async {
      final api = await callADriver(tester);
      await tester.tap(find.byKey(const Key('dispatch_driver_agreed_no')));
      await _settle(tester);
      expect(api.cancels, 0);
      expect(find.byKey(const Key('dispatch_status_TIER1_NOTIFIED')), findsOneWidget);
      // Asked once per call, not on every return.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(find.text('Did a driver agree to come?'), findsNothing);
    });
  });

  testWidgets('Call/SMS rows scroll without overlap at 320 dp and 130% text', (tester) async {
    SharedPreferences.setMockInitialValues(_contactsPrefs(drivers: 8));
    _screen(tester, const Size(320, 568));
    await _open(tester, [_dispatch('FAILED')], textScale: 1.3);
    expect(tester.takeException(), isNull);

    final last = find.byKey(const Key('call_+233240001007'), skipOffstage: false);
    await tester.scrollUntilVisible(last, 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('dispatch_scroll')), matching: find.byType(Scrollable)));
    await tester.ensureVisible(last);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(last.hitTestable(), findsOneWidget, reason: 'reachable and not covered');

    // Rows (stacked on this narrow screen) never overlap each other.
    final rects = [
      for (var i = 0; i < 8; i++)
        if (find.byKey(Key('call_+23324000${1000 + i}')).evaluate().isNotEmpty)
          tester.getRect(find.byKey(Key('call_+23324000${1000 + i}'))),
    ];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, greaterThanOrEqualTo(rects[i - 1].bottom), reason: 'row $i');
    }
    final sms = tester.getRect(find.byKey(const Key('sms_+233240001007')));
    expect(sms.overlaps(tester.getRect(last)), isFalse);
    expect(tester.getSize(last).height, greaterThanOrEqualTo(48));
    // Who each button contacts is read out.
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Call Driver 8'), findsOneWidget);
    expect(find.bySemanticsLabel('SMS Driver 8'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('done steps show their time from the API, in the phone\'s local time',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, [_dispatch('HOSPITAL_NOTIFIED', driver: 'Ibrahim')]);
    final ctx = tester.element(find.byType(DispatchStatusScreen));
    final accepted = DateTime.parse('2026-11-09T09:17:00+00:00');
    final shown = shortWhen(ctx, accepted);
    expect(find.text(shown), findsOneWidget);
    expect(find.byKey(const Key('timeline_driver_time')), findsOneWidget);
    // The current and future steps have no time.
    expect(find.byKey(const Key('timeline_hospital_time')), findsNothing);
    expect(find.byKey(const Key('timeline_trip_time')), findsNothing);
    // Read as one sentence with its time.
    expect(find.bySemanticsLabel('Done: Driver accepted at $shown, Ibrahim'), findsOneWidget);
    // Never a raw timestamp.
    expect(find.textContaining('2026-11-09T'), findsNothing);
    handle.dispose();
  });
}
