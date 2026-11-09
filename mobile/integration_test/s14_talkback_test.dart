/// Round 6: TalkBack really on, on each main screen. The host records what the
/// accessibility tree offers TalkBack, in reading order, with a screenshot of TalkBack
/// running (`build/emulator_pass/<avd>/talkback_*.txt` and `.png`). It also fails the run if a
/// control has no name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'support/harness.dart';

class _Accepted extends ApiClient {
  @override
  Future<Map<String, dynamic>> getDispatch(int id) async => {
        'id': id,
        'referral_id': 4821,
        'facility_id': 1,
        'facility_name': facilityName,
        'driver_name': 'Ibrahim',
        'driver_vehicle': 'Motor-King, Red tricycle',
        'status': 'HOSPITAL_NOTIFIED',
        'current_tier': 1,
      };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  flow('TalkBack reads each main screen', (tester) async {
    await tester.setUpCho();
    await tester.wait(const Duration(seconds: 2));
    await Host.call('/talkback', {'on': '1'});
    try {
      final screens = <(String, Widget)>[
        ('home', const HomeScreen(acousticEnabled: true)),
        ('vitals', VitalsScreen(result: moewsOnlyResult())),
        (
          'result',
          ResultScreen(
            result: moewsOnlyResult(),
            vitals: const {
              'systolic_bp': 142,
              'diastolic_bp': 80,
              'heart_rate': 118,
              'respiratory_rate': 18,
              'temperature': 37.0,
              'spo2': 98,
              'consciousness_level': 'A',
            },
            moews: calculateMoews(
                sbp: 142, dbp: 80, hr: 118, rr: 18, temp: 37.0, spo2: 98, consciousness: 'A'),
          ),
        ),
        ('form', const ReferralScreen()),
        (
          'status',
          DispatchStatusScreen(
              dispatchId: 9, clientRequestId: 'tb', facilityId: 1, api: _Accepted()),
        ),
      ];
      for (final (name, screen) in screens) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(
          theme: buildYomaTheme(),
          debugShowCheckedModeBanner: false,
          home: screen,
        ));
        await tester.wait(const Duration(seconds: 3));
        final read = ((await Host.call('/talkback-read', {'name': name})) as Map)['read'] as List;
        await Host.note(
            'TalkBack on $name reads ${read.length} items: ${read.take(12).join(' | ')}');
        expect(read, isNotEmpty, reason: 'TalkBack finds nothing on $name');
        // Every button or edit box has words of its own.
        for (final item in read.cast<String>()) {
          expect(item.startsWith('(') && item.endsWith(')'), isFalse,
              reason: 'unnamed control on $name');
        }
      }
    } finally {
      await Host.call('/talkback', {'on': '0'});
    }
  });
}
