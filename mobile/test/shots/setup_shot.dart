import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/setup_screen.dart';
import 'package:yoma_triage/services/api_client.dart';

import 'shot.dart';

class _Refuse extends ApiClient {
  @override
  Future<Map<String, dynamic>> lookupCho(String phone) async =>
      throw ApiException(404, '{"detail":"x","code":"CHO_NOT_REGISTERED"}');
}

void main() {
  setUpAll(loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('setup', (tester) async {
    await pumpPhone(tester, SetupScreen(api: _Refuse(), onComplete: (_) {}));
    await shot(tester, 'setup_empty');
    await tester.enterText(find.byKey(const Key('setup_phone')), '240999999');
    await settle(tester);
    await shot(tester, 'setup_typed');
    await tester.tap(find.byKey(const Key('setup_continue')));
    await settle(tester);
    await shot(tester, 'setup_refused');
  });
}
