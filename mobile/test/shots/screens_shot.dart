// Renders the round-5 fidelity screens with the real fonts at 360×640 dp into
// build/shots/. Local tool: flutter test test/shots/screens_shot.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/contacts_store.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/screening_service.dart';

import '../helpers/cho_helper.dart';
import 'shot.dart';

ResultScreen _result(Map<String, Object?> v, {ScreeningResult? screening}) => ResultScreen(
      result: screening ?? moewsOnlyResult(),
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

Map<String, Object?> _v({
  int? sbp = 118,
  int? dbp = 76,
  int? hr = 72,
  int? rr = 16,
  double? temp = 36.8,
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

ScreeningResult _acoustic(String label) => ScreeningResult(
      label: label,
      confidence: 0.7,
      reason: 'test',
      source: 'yamnet',
      modelVersion: 'test',
    );

/// A breathing check that records nothing; the result waits for [classify].
class _Breathing extends ScreeningService {
  _Breathing({this.failStart, this.label});

  final Object? failStart;
  final String? label;
  final classify = Completer<ScreeningResult>();

  @override
  Future<void> startRecording() async {
    if (failStart != null) throw failStart!;
  }

  @override
  Stream<double> microphoneLevels() =>
      Stream.periodic(const Duration(milliseconds: 120), (_) => 0.8);

  @override
  Future<ScreeningResult> stopAndClassify() =>
      label == null ? classify.future : Future.value(_acoustic(label!));

  @override
  void cancelAnalysis() {}

  @override
  Future<void> dispose() async {}
}

class _Dispatch extends ApiClient {
  _Dispatch(this.body);

  final Map<String, dynamic> body;

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async => body;
}

Map<String, dynamic> _dispatch(String status,
    {String? driver, bool late = false, Map<String, String?> times = const {}}) {
  final today = DateTime.now();
  String at(int h, int m) =>
      DateTime(today.year, today.month, today.day, h, m).toUtc().toIso8601String();
  return {
    'id': 9,
    'referral_id': 4821,
    'facility_id': 1,
    'facility_name': 'Tamale Teaching Hospital',
    'diverted_from': null,
    'driver_name': driver,
    'status': status,
    'current_tier': 1,
    'late_claim_until':
        late ? DateTime.now().toUtc().add(const Duration(minutes: 38)).toIso8601String() : null,
    'step_times': {
      'sent': at(9, 12),
      'drivers_notified': at(9, 13),
      'driver_accepted': null,
      'hospital_notified': null,
      'hospital_confirmed': null,
      'diverted': null,
      'completed': null,
      ...{
        for (final e in times.entries)
          e.key: e.value == null
              ? null
              : at(int.parse(e.value!.split(':')[0]), int.parse(e.value!.split(':')[1]))
      },
    },
  };
}

Widget _dispatchScreen(Map<String, dynamic> body) => DispatchStatusScreen(
      dispatchId: 9,
      clientRequestId: 'req-1',
      facilityId: 1,
      api: _Dispatch(body),
      launcher: (_) async => true,
    );

Map<String, Object> _prefs() => {
      ...registeredChoPrefs(),
      ContactsStore.prefsKey: jsonEncode({
        'compound_id': 1,
        'drivers': [
          for (final (i, name) in ['Driver A', 'Driver B', 'Driver C'].indexed)
            {'name': name, 'phone': '+23324000${1000 + i}', 'is_motor_king': i == 0},
        ],
        'facilities': [
          {'id': 1, 'name': 'Tamale Teaching Hospital', 'phone': '+233240000200'},
        ],
      }),
      ContactsStore.updatedAtPrefsKey: DateTime.now().toUtc().toIso8601String(),
    };

Future<void> _fresh(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(const SizedBox());
  await pumpPhone(tester, screen);
}

void main() {
  setUpAll(loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues(_prefs()));

  testWidgets('result', (tester) async {
    await _fresh(tester, _result(_v(sbp: 185, hr: 118, rr: 32)));
    await shot(tester, 'result_critical');
    await _fresh(tester, _result(_v(sbp: 142, hr: 108)));
    await shot(tester, 'result_elevated');
    await _fresh(tester, _result(_v(spo2: null)));
    await shot(tester, 'result_stable');
    await _fresh(tester, _result(_v(sbp: null, dbp: null, temp: null, avpu: null)));
    await shot(tester, 'result_incomplete');
    await _fresh(tester, _result(_v(sbp: 142, hr: 108), screening: _acoustic('RED')));
    await shot(tester, 'result_breathing_advisory');
  });

  testWidgets('dispatch', (tester) async {
    await _fresh(tester, _dispatchScreen(_dispatch('TIER1_NOTIFIED')));
    await shot(tester, 'dispatch_waiting');
    await _fresh(
        tester,
        _dispatchScreen(_dispatch('HOSPITAL_NOTIFIED',
            driver: 'Driver A', times: {'driver_accepted': '9:17', 'hospital_notified': '9:17'})));
    await shot(tester, 'dispatch_accepted');
    await _fresh(
        tester,
        _dispatchScreen(_dispatch('HOSPITAL_CONFIRMED', driver: 'Driver A', times: {
          'driver_accepted': '9:17',
          'hospital_notified': '9:17',
          'hospital_confirmed': '9:20',
        })));
    await shot(tester, 'dispatch_confirmed');
    await _fresh(
        tester,
        _dispatchScreen(_dispatch('COMPLETED', driver: 'Driver A', times: {
          'driver_accepted': '9:17',
          'hospital_notified': '9:17',
          'hospital_confirmed': '9:20',
          'completed': '9:58',
        })));
    await shot(tester, 'dispatch_completed');
    await _fresh(tester, _dispatchScreen(_dispatch('FAILED', late: true)));
    await shot(tester, 'dispatch_no_driver');
  });

  testWidgets('dispatch: late acceptance', (tester) async {
    final api = _Dispatch(_dispatch('FAILED', late: true));
    await _fresh(
        tester,
        DispatchStatusScreen(
            dispatchId: 9,
            clientRequestId: 'r',
            facilityId: 1,
            api: api,
            launcher: (_) async => true));
    api.body
      ..clear()
      ..addAll(_dispatch('HOSPITAL_NOTIFIED',
          driver: 'Driver B',
          late: true,
          times: {'driver_accepted': '9:41', 'hospital_notified': '9:41'}));
    await tester.pump(const Duration(seconds: 31));
    await settle(tester);
    await shot(tester, 'dispatch_late_accepted');
  });

  testWidgets('dispatch: did a driver agree', (tester) async {
    await _fresh(tester, _dispatchScreen(_dispatch('TIER1_NOTIFIED')));
    await tester.tap(find.text('Call a driver instead'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('call_+233240001000')));
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    await shot(tester, 'dispatch_did_driver_agree');
  });

  testWidgets('breathing', (tester) async {
    await _fresh(tester,
        ScreeningScreen(forceWebSimulator: false, service: _Breathing(), showReadyStep: true));
    await shot(tester, 'breathing_ready');

    final analysing = _Breathing();
    await _fresh(tester, ScreeningScreen(forceWebSimulator: false, service: analysing));
    await shot(tester, 'breathing_recording');
    await tester.tap(find.text('Stop'));
    await settle(tester);
    await shot(tester, 'breathing_analysing');

    for (final label in ['RED', 'INCONCLUSIVE']) {
      await _fresh(
          tester,
          ScreeningScreen(
              forceWebSimulator: false, service: _Breathing(label: label), showResultStep: true));
      await tester.tap(find.text('Stop'));
      await settle(tester);
      await shot(tester, 'breathing_result_${label.toLowerCase()}');
    }

    await _fresh(
        tester,
        ScreeningScreen(
            forceWebSimulator: false,
            service: _Breathing(failStart: StateError('Microphone permission denied'))));
    await shot(tester, 'breathing_mic_blocked');
  });

  testWidgets('home', (tester) async {
    await _fresh(tester, HomeScreen(acousticEnabled: true, online: Stream.value(true)));
    await shot(tester, 'home_acoustic');
    await _fresh(tester, HomeScreen(acousticEnabled: false, online: Stream.value(false)));
    await shot(tester, 'home_moews_offline');
  });
}
