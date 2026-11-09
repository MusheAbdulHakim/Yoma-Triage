import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/screening_result.dart';

import 'shot.dart';

void main() {
  setUpAll(loadFonts);
  testWidgets('vitals', (tester) async {
    await pumpPhone(tester, VitalsScreen(result: moewsOnlyResult()));
    await shot(tester, 'vitals_empty');
    final avpu = tester.getRect(find.byKey(const Key('vitals_avpu')));
    final button = tester.getRect(find.byKey(const Key('vitals_see_result')));
    // ignore: avoid_print
    print('avpu $avpu button $button');
    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await settle(tester);
    await shot(tester, 'vitals_flagged');
  });
}
