import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('web simulator Code Red shows Confirm Referral', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScreeningScreen(forceWebSimulator: true),
      ),
    );
    expect(find.text('Demo Code Red'), findsOneWidget);
    await tester.tap(find.text('Demo Code Red'));
    await tester.pumpAndSettle();
    expect(find.text('RED'), findsOneWidget);
    expect(find.text('Confirm Referral'), findsOneWidget);
    expect(find.text('Continue Monitoring'), findsOneWidget);
  });
}
