import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Home shows Screen Breathing and Emergency Referral',
      (tester) async {
    await tester.pumpWidget(const YomaApp());
    expect(find.text('Screen Breathing'), findsOneWidget);
    expect(find.text('Emergency Referral'), findsOneWidget);
  });

  testWidgets('Emergency Referral bypasses screening', (tester) async {
    await tester.pumpWidget(const YomaApp());
    await tester.tap(find.text('Emergency Referral'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vitals'), findsWidgets);
  });
}
