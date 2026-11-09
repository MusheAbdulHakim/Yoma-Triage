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
  _Dispatch(this.status, {this.driver, this.divertedFrom, this.facility = 'Tamale Teaching Hospital'});

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
        builder: (context, child) => MediaQuery(
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
  });
}
