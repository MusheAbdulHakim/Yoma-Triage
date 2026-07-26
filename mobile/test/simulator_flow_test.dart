import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('screening early-stop shows Confirm Referral', (tester) async {
    await tester.pumpWidget(const YomaApp());
    await tester.tap(find.text('Screen Breathing'));
    await tester.pumpAndSettle();

    // VM tests use Android capture UI (kIsWeb == false).
    expect(find.text('Stop & Analyze Early'), findsOneWidget);
    await tester.tap(find.text('Stop & Analyze Early'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Referral'), findsOneWidget);
  });
}
