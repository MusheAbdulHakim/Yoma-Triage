/// UI redesign round 1: every redesigned screen and state, on a device, so the
/// screenshots can sit next to the Stitch designs. Run at the device's own size ('ui')
/// and at 320×568 dp (as part of '9'), where the harness also checks nothing is cut off.
///
/// Screens are opened directly with the states the designs show, so no referrals have to
/// be built up first. Home's warning counters are set on OfflineQueue.shared, as in s9.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'support/harness.dart';

Map<String, Object?> _vitals({
  int? sbp = 120,
  int? dbp = 80,
  int? hr = 80,
  int? rr = 18,
  double? temp = 37.0,
  int? spo2 = 98,
  String? avpu = 'A',
}) =>
    {
      'systolic_bp': sbp,
      'diastolic_bp': dbp,
      'heart_rate': hr,
      'respiratory_rate': rr,
      'temperature': temp,
      'spo2': spo2,
      'consciousness_level': avpu,
    };

Widget _result(Map<String, Object?> v) => ResultScreen(
      result: moewsOnlyResult(),
      vitals: v,
      moews: calculateMoews(
        sbp: v['systolic_bp'] as int?,
        dbp: v['diastolic_bp'] as int?,
        hr: v['heart_rate'] as int?,
        rr: v['respiratory_rate'] as int?,
        temp: v['temperature'] as double?,
        spo2: v['spo2'] as int?,
        consciousness: v['consciousness_level'] as String?,
      ),
    );

/// A dispatch that always reports one status, for the round-3 screenshots.
class _Dispatch extends ApiClient {
  _Dispatch(this.status,
      {this.driver, this.divertedFrom, this.facility = 'Tamale Teaching Hospital'});

  final String status;
  final String? driver;
  final String? divertedFrom;
  final String facility;

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async => {
        'id': id,
        'referral_id': 4821,
        'facility_id': 1,
        'facility_name': facility,
        'diverted_from': divertedFrom,
        'driver_name': driver,
        'status': status,
        'current_tier': 1,
      };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('UI redesign screens', (tester) async {
    await tester.setUpCho();
    await tester.wait(const Duration(seconds: 3));
    final queue = OfflineQueue.shared;

    Future<void> show(Widget screen, {double textScale = 1.0}) async {
      // A fresh screen each time, not the previous one's state.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(MaterialApp(
        theme: buildYomaTheme(),
        debugShowCheckedModeBanner: false,
        // Only when asked: otherwise the system text size (Settings) applies.
        builder: (context, child) => textScale == 1.0
            ? child!
            : MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
        home: screen,
      ));
      await tester.wait(const Duration(seconds: 2));
    }

    void clearWarnings() {
      queue.failedCount.value = 0;
      queue.needsConfirmationCount.value = 0;
      queue.expiringCount.value = 0;
      queue.retryWarning.value = null;
    }

    // Home, MOEWS-only and acoustic, no warnings.
    await show(const HomeScreen(acousticEnabled: false));
    clearWarnings();
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('ui_home_moews_only');
    await show(const HomeScreen(acousticEnabled: true));
    clearWarnings();
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('ui_home_acoustic');

    // Light strip: waiting only.
    await show(const HomeScreen(acousticEnabled: false));
    clearWarnings();
    queue.expiringCount.value = 1;
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('ui_home_strip_light');

    // Navy strip: a failed referral, closed and open.
    clearWarnings();
    queue.failedCount.value = 1;
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('ui_home_strip_failed');
    await tester.tapOn(find.byKey(const Key('home_warnings_summary')));
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('ui_home_strip_failed_open');

    // Every warning, open, at 130% text: Emergency referral must stay whole.
    await show(const HomeScreen(acousticEnabled: true), textScale: 1.3);
    queue.failedCount.value = 2;
    queue.expiringCount.value = 3;
    queue.retryWarning.value = 'Could not send. Will retry when there is signal.';
    await tester.wait(const Duration(milliseconds: 500));
    await tester.tapOn(find.byKey(const Key('home_warnings_summary')));
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('ui_home_all_warnings_130');
    clearWarnings();

    // Record vitals: empty, then partly filled with one field not measured.
    await show(VitalsScreen(result: moewsOnlyResult()));
    await tester.shot('ui_vitals_empty');
    await tester.enterText(find.byKey(const Key('vitals_hr')), '96');
    await tester.tapOn(find.byKey(const Key('vitals_rr_not_measured')));
    await tester.closeKeyboard();
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('ui_vitals_partial');
    await show(VitalsScreen(result: moewsOnlyResult()), textScale: 1.3);
    await tester.shot('ui_vitals_130');

    // Result, the four levels.
    await show(_result(_vitals(sbp: 185, rr: 32, hr: 118)));
    await tester.shot('ui_result_red');
    await show(_result(_vitals(hr: 118, sbp: 142)));
    await tester.shot('ui_result_amber');
    await show(_result(_vitals(spo2: null)));
    await tester.shot('ui_result_green');
    await show(_result(_vitals(sbp: null, dbp: null, temp: null, avpu: null)));
    await tester.shot('ui_result_incomplete');
    await show(_result(_vitals(sbp: 185, rr: 32, hr: 118)), textScale: 1.3);
    await tester.shot('ui_result_red_130');

    // Emergency referral form, opened from Home (no vitals) and after vitals.
    await show(const ReferralScreen());
    await tester.shot('ui_referral_no_vitals');
    await show(ReferralScreen(initialVitals: _vitals(sbp: 185, rr: 32, hr: 118)));
    await tester.shot('ui_referral_with_vitals');
    await show(const ReferralScreen(), textScale: 1.3);
    await tester.shot('ui_referral_130');

    // ---- Round 3 ----
    // Form: no vitals, no type (Send disabled); with RED vitals and a type chosen.
    await show(const ReferralScreen());
    await tester.shot('r3_form_no_vitals_disabled');
    await show(ReferralScreen(initialVitals: _vitals(sbp: 185, rr: 32, hr: 118)));
    await tester.tapOn(find.byKey(const Key('referral_type_pph')));
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('r3_form_with_vitals_type_selected');

    Widget dispatch(String status, {String? driver, String? divertedFrom, String? facility}) =>
        DispatchStatusScreen(
          dispatchId: 9,
          clientRequestId: 'shot',
          facilityId: 1,
          api: _Dispatch(status,
              driver: driver,
              divertedFrom: divertedFrom,
              facility: facility ?? 'Tamale Teaching Hospital'),
          launcher: (_) async => true,
        );
    for (final (name, screen) in [
      ('r3_status_1_waiting', dispatch('TIER1_NOTIFIED')),
      ('r3_status_2_accepted', dispatch('HOSPITAL_NOTIFIED', driver: 'Ibrahim')),
      ('r3_status_2b_on_the_way', dispatch('HOSPITAL_CONFIRMED', driver: 'Ibrahim')),
      ('r3_status_3_no_driver', dispatch('FAILED')),
      (
        'r3_status_4_diverted',
        dispatch('HOSPITAL_NOTIFIED',
            driver: 'Ibrahim',
            divertedFrom: 'Tamale Teaching Hospital',
            facility: 'Sagnarigu Polyclinic'),
      ),
      ('r3_status_6_arrived', dispatch('COMPLETED', driver: 'Ibrahim')),
    ]) {
      await show(screen);
      await tester.shot(name);
    }
    await show(dispatch('TIER1_NOTIFIED'));
    await tester.tapOn(find.byKey(const Key('dispatch_call_instead')));
    await tester.wait(const Duration(milliseconds: 500));
    await tester.shot('r3_status_1b_call_instead');
    await show(dispatch('FAILED'), textScale: 1.3);
    await tester.shot('r3_status_3_no_driver_130');
    await show(const QueuedReferralScreen(clientRequestId: 'shot', facilityId: 1));
    await tester.shot('r3_status_5_not_sent_yet');

    await _rounds4to6(tester, show, clearWarnings);
  });
}

/// A dispatch whose answer the test changes between polls, with step times and the vehicle.
class _Live extends ApiClient {
  _Live(this.body);

  Map<String, dynamic> body;
  int cancels = 0;

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async => body;

  @override
  Future<Map<String, dynamic>> cancelDispatch({
    required int dispatchId,
    required String choPhone,
  }) async {
    cancels++;
    body = {...body, 'status': 'CANCELLED'};
    return {'status': 'CANCELLED'};
  }
}

Map<String, dynamic> _trip(
  String status, {
  String? driver,
  String? vehicle,
  String facility = facilityName,
  String? divertedFrom,
  Duration? lateWindow,
  List<String> done = const [],
}) {
  final today = DateTime.now();
  String at(int h, int m) =>
      DateTime(today.year, today.month, today.day, h, m).toUtc().toIso8601String();
  const times = {
    'sent': (9, 12),
    'drivers_notified': (9, 13),
    'driver_accepted': (9, 17),
    'hospital_notified': (9, 17),
    'hospital_confirmed': (9, 20),
    'diverted': (9, 24),
    'completed': (9, 58),
  };
  return {
    'id': 9,
    'referral_id': 4821,
    'facility_id': 1,
    'facility_name': facility,
    'diverted_from': divertedFrom,
    'driver_name': driver,
    'driver_vehicle': vehicle,
    'status': status,
    'current_tier': 1,
    'late_claim_until':
        lateWindow == null ? null : DateTime.now().toUtc().add(lateWindow).toIso8601String(),
    'step_times': {
      for (final MapEntry(:key, value: (h, m)) in times.entries)
        key: (key == 'sent' || key == 'drivers_notified' || done.contains(key)) ? at(h, m) : null,
    },
  };
}

/// Rounds 4-6: the states added since round 3, and what only a device can show.
Future<void> _rounds4to6(
  WidgetTester tester,
  Future<void> Function(Widget, {double textScale}) show,
  void Function() clearWarnings,
) async {
  // ---- Home ----
  await show(HomeScreen(acousticEnabled: false, online: Stream.value(false)));
  clearWarnings();
  await tester.wait(const Duration(milliseconds: 500));
  await tester.shot('r6_home_moews_offline');
  await show(HomeScreen(acousticEnabled: true, online: Stream.value(false)));
  clearWarnings();
  await tester.wait(const Duration(milliseconds: 500));
  await tester.shot('r6_home_acoustic_offline');

  // ---- Record vitals: partly filled, then See result with gaps ----
  await show(VitalsScreen(result: moewsOnlyResult()));
  await tester.enterText(find.byKey(const Key('vitals_sbp')), '120');
  await tester.enterText(find.byKey(const Key('vitals_dbp')), '80');
  await tester.closeKeyboard();
  await tester.shot('r6_vitals_partial');
  await tester.tapOn(find.byKey(const Key('vitals_see_result')));
  await tester.wait(const Duration(milliseconds: 800));
  await tester.shot('r6_vitals_see_result_gaps');

  // The keyboard must never hide the focused field or the main button.
  for (final key in ['vitals_hr', 'vitals_temp', 'vitals_spo2']) {
    await show(VitalsScreen(result: moewsOnlyResult()));
    final field = find.byKey(Key(key));
    await tester.reveal(field);
    await tester.tap(field);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (tester.view.viewInsets.bottom == 0 && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.wait(const Duration(milliseconds: 800));
    final ratio = tester.view.devicePixelRatio;
    final visibleBottom = (tester.view.physicalSize.height - tester.view.viewInsets.bottom) / ratio;
    final keyboard = tester.view.viewInsets.bottom / ratio;
    final fieldBottom = tester.getRect(field).bottom;
    final button = find.byKey(const Key('vitals_see_result'));
    final buttonBottom = tester.getRect(button).bottom;
    await Host.note('Keyboard on $key: ${keyboard.round()} dp high; field bottom '
        '${fieldBottom.round()}, button bottom ${buttonBottom.round()}, '
        'visible to ${visibleBottom.round()}');
    await tester.shot('r6_keyboard_$key');
    if (keyboard == 0) {
      await Host.call('/problem', {'text': 'No soft keyboard appeared for $key'});
    } else {
      expect(fieldBottom, lessThanOrEqualTo(visibleBottom), reason: '$key hidden by keyboard');
      expect(buttonBottom, lessThanOrEqualTo(visibleBottom),
          reason: 'See result hidden by keyboard ($key)');
    }
    await tester.closeKeyboard();
  }

  // ---- Result: the four variants (re-shot: word and score only, amber card) + advisory ----
  await show(_result(_vitals(sbp: 185, rr: 32, hr: 118)));
  await tester.shot('r6_result_critical');
  await show(_result(_vitals(hr: 118, sbp: 142)));
  await tester.shot('r6_result_elevated');
  await show(_result(_vitals(spo2: null)));
  await tester.shot('r6_result_stable');
  await show(_result(_vitals(sbp: null, dbp: null, temp: null, avpu: null)));
  await tester.shot('r6_result_incomplete');
  await show(ResultScreen(
    result: ScreeningResult(
        label: 'RED', confidence: 0.7, reason: 'device', source: 'yamnet', modelVersion: 'v'),
    vitals: _vitals(hr: 118, sbp: 142),
    moews: calculateMoews(
        sbp: 142, dbp: 80, hr: 118, rr: 18, temp: 37.0, spo2: 98, consciousness: 'A'),
  ));
  await tester.shot('r6_result_breathing_advisory');

  // ---- Referral form ----
  await show(const ReferralScreen());
  await tester.shot('r6_form_no_type');
  await tester.tapOn(find.byKey(const Key('referral_type_pph')));
  await tester.wait(const Duration(milliseconds: 500));
  await tester.shot('r6_form_type_no_vitals');
  await show(ReferralScreen(initialVitals: _vitals(sbp: 165, dbp: 112, hr: 118, rr: 24)));
  await tester.tapOn(find.byKey(const Key('referral_type_pph')));
  await tester.wait(const Duration(milliseconds: 500));
  await tester.shot('r6_form_type_with_vitals');

  // ---- Dispatch status: every state ----
  Widget status(_Live api, {bool realLauncher = false}) => realLauncher
      ? DispatchStatusScreen(dispatchId: 9, clientRequestId: 'shot', facilityId: 1, api: api)
      : DispatchStatusScreen(
          dispatchId: 9,
          clientRequestId: 'shot',
          facilityId: 1,
          api: api,
          launcher: (_) async => true);
  const accepted = ['driver_accepted', 'hospital_notified'];
  for (final (name, body) in [
    ('r6_status_waiting', _trip('TIER1_NOTIFIED')),
    (
      'r6_status_accepted',
      _trip('HOSPITAL_NOTIFIED',
          driver: 'Ibrahim', vehicle: 'Motor-King, Red tricycle', done: accepted)
    ),
    (
      'r6_status_confirmed',
      _trip('HOSPITAL_CONFIRMED',
          driver: 'Ibrahim',
          vehicle: 'Motor-King, Red tricycle',
          done: [...accepted, 'hospital_confirmed'])
    ),
    (
      'r6_status_arrived',
      _trip('COMPLETED',
          driver: 'Ibrahim',
          vehicle: 'Motor-King, Red tricycle',
          done: [...accepted, 'hospital_confirmed', 'completed'])
    ),
    ('r6_status_no_driver', _trip('FAILED', lateWindow: const Duration(minutes: 38))),
    (
      'r6_status_diverted',
      _trip('HOSPITAL_NOTIFIED',
          driver: 'Ibrahim',
          vehicle: 'Motor-King, Red tricycle',
          facility: 'Sagnarigu Polyclinic',
          divertedFrom: facilityName,
          done: [...accepted, 'diverted'])
    ),
  ]) {
    await show(status(_Live(body)));
    await tester.shot(name);
  }

  // Late acceptance: FAILED, then a driver accepts inside the window (checked every 30 s).
  final late = _Live(_trip('FAILED', lateWindow: const Duration(minutes: 38)));
  await show(status(late));
  late.body = _trip('HOSPITAL_NOTIFIED',
      driver: 'Amina',
      vehicle: 'Personal vehicle',
      lateWindow: const Duration(minutes: 38),
      done: accepted);
  await tester.waitFor(find.textContaining('Accepted after the alerts had stopped'),
      timeout: const Duration(seconds: 45));
  await tester.shot('r6_status_late_accepted');

  // Call a driver instead, with the real dialler; on return, "Did a driver agree to come?".
  final waiting = _Live(_trip('TIER1_NOTIFIED'));
  await show(status(waiting, realLauncher: true));
  await tester.tapOn(find.byKey(const Key('dispatch_call_instead')));
  await tester.waitFor(find.byKey(const Key('call_$motorKingDriver')));
  await tester.tapOn(find.byKey(const Key('call_$motorKingDriver')));
  final dialler = await Host.externalApp('r6_dialler');
  await Host.note('Call a driver instead opened ${dialler['package']}');
  expect(dialler['package'], isNot('gh.yomatriage.yoma_triage'), reason: 'dialler did not open');
  await tester.waitFor(find.text('Did a driver agree to come?'));
  await tester.shot('r6_status_did_driver_agree');
  await tester.tapOn(find.byKey(const Key('dispatch_driver_agreed_no')));
  await tester.wait(const Duration(milliseconds: 500));
  expect(waiting.cancels, 0, reason: 'No keeps waiting');
  await tester.tapOn(find.byKey(const Key('sms_$motorKingDriver')));
  final messaging = await Host.externalApp('r6_messaging');
  await Host.note('SMS opened ${messaging['package']}');
  expect(messaging['package'], isNot('gh.yomatriage.yoma_triage'),
      reason: 'messaging did not open');
  await tester.wait(const Duration(seconds: 1));

  // ---- Android back (a real key press) from each screen opened from Home ----
  for (final (key, landing) in [
    ('home_emergency_referral', find.byType(ReferralScreen)),
    ('home_record_vitals', find.byType(VitalsScreen)),
    ('home_check_breathing', find.byType(ScreeningScreen)),
  ]) {
    await show(HomeScreen(acousticEnabled: true, online: Stream.value(true)));
    clearWarnings();
    await tester.tapOn(find.byKey(Key(key)));
    await tester.wait(const Duration(seconds: 1));
    expect(landing, findsWidgets, reason: '$key opened');
    await Host.back();
    await tester.wait(const Duration(seconds: 1));
    expect(find.byType(HomeScreen).hitTestable(), findsOneWidget, reason: 'back from $key');
  }
  // Back from the status screen and from Result returns to the screen underneath.
  for (final (name, screen) in [
    ('status', status(_Live(_trip('TIER1_NOTIFIED')))),
    ('result', _result(_vitals(sbp: 185, rr: 32, hr: 118))),
  ]) {
    await show(const HomeScreen(acousticEnabled: false));
    final context = tester.element(find.byType(HomeScreen));
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    await tester.wait(const Duration(seconds: 1));
    await Host.back();
    await tester.wait(const Duration(seconds: 1));
    expect(find.byType(HomeScreen).hitTestable(), findsOneWidget, reason: 'back from $name');
  }

  // ---- 130% system text size (Settings), not just the app's own scaling ----
  await Host.fontScale(1.3);
  await tester.wait(const Duration(seconds: 2));
  for (final (name, screen) in <(String, Widget)>[
    ('r6_sys130_home', const HomeScreen(acousticEnabled: true)),
    ('r6_sys130_vitals', VitalsScreen(result: moewsOnlyResult())),
    ('r6_sys130_result', _result(_vitals(spo2: null))),
    ('r6_sys130_form', const ReferralScreen()),
    ('r6_sys130_status', status(_Live(_trip('FAILED', lateWindow: const Duration(minutes: 38))))),
  ]) {
    await show(screen);
    clearWarnings();
    expect(tester.takeException(), isNull, reason: name);
    await tester.shot(name);
  }
  await Host.fontScale(1.0);
  await tester.wait(const Duration(seconds: 2));
}
