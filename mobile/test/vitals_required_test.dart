import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';
import 'package:yoma_triage/widgets/yoma_components.dart';

import 'helpers/cho_helper.dart';
import 'helpers/vitals_helper.dart';

String _buttonLabel(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(const Key('vitals_see_result')), matching: find.byType(Text)))
    .data!;

Future<void> _open(WidgetTester tester, {Size size = const Size(1000, 2600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    home: VitalsScreen(result: moewsOnlyResult()),
  ));
  await tester.pumpAndSettle();
}

/// The card's border colour, for the vital whose field has [fieldKey].
Color _cardBorder(WidgetTester tester, Finder inside) {
  final card = tester.widget<YomaCard>(
      find.ancestor(of: inside, matching: find.byType(YomaCard)).first);
  return card.borderColor;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(registeredChoPrefs()));

  testWidgets('"N left" counts the five required vitals; SpO2 never counts', (tester) async {
    await _open(tester);
    expect(_buttonLabel(tester), 'See result – 5 left');

    await tester.enterText(find.byKey(const Key('vitals_spo2')), '98');
    await tester.pump();
    expect(_buttonLabel(tester), 'See result – 5 left', reason: 'SpO2 is optional');

    await tester.enterText(find.byKey(const Key('vitals_sbp')), '120');
    await tester.pump();
    expect(_buttonLabel(tester), 'See result – 5 left', reason: 'BP needs both values');
    await tester.enterText(find.byKey(const Key('vitals_dbp')), '80');
    await tester.pump();
    expect(_buttonLabel(tester), 'See result – 4 left', reason: 'BP is one item');

    await tester.tap(find.byKey(const Key('vitals_hr_not_measured')));
    await tester.pump();
    expect(_buttonLabel(tester), 'See result – 3 left', reason: 'not measured is an answer');

    await tester.enterText(find.byKey(const Key('vitals_rr')), '18');
    await tester.enterText(find.byKey(const Key('vitals_temp')), '37.0');
    await selectAvpu(tester);
    expect(_buttonLabel(tester), 'See result');
  });

  testWidgets('messages say "tap Not measured", never "tick"', (tester) async {
    await _open(tester);
    await tester.enterText(find.byKey(const Key('vitals_hr')), '');
    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a value or tap Not measured'), findsWidgets);
    expect(find.text('Enter both values or tap Not measured'), findsOneWidget);
    expect(find.textContaining('tick'), findsNothing);
  });

  testWidgets('Oxygen saturation is marked optional and may be left blank', (tester) async {
    await _open(tester);
    expect(find.text('(optional)'), findsOneWidget);
    await fillVitals(tester, overrides: const {'spo2': ''});
    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await tester.pumpAndSettle();
    final result = tester.widget<ResultScreen>(find.byType(ResultScreen));
    expect(result.vitals!['spo2'], isNull);
  });

  testWidgets('See result with gaps scrolls to the first missing vital, marks and announces it',
      (tester) async {
    final announced = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final data = (message as Map)['data'] as Map?;
        if (data?['message'] case final String text) announced.add(text);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));

    await _open(tester, size: const Size(360, 640));
    // Everything except consciousness, the last card.
    for (final (key, value) in [
      ('vitals_sbp', '120'),
      ('vitals_dbp', '80'),
      ('vitals_hr', '80'),
      ('vitals_rr', '18'),
      ('vitals_temp', '37.0'),
    ]) {
      await tester.enterText(find.byKey(Key(key)), value);
    }
    await tester.pump();
    // Start at the top, the way a CHO would have scrolled back up.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 600));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await tester.pumpAndSettle();

    expect(find.byType(ResultScreen), findsNothing, reason: 'stays enabled but cannot continue');
    final avpu = find.byKey(const Key('vitals_avpu'));
    final viewport = tester.getRect(find.byType(SingleChildScrollView));
    final top = tester.getTopLeft(avpu).dy;
    expect(top, inInclusiveRange(viewport.top, viewport.bottom - 48), reason: 'scrolled to');
    expect(_cardBorder(tester, find.byKey(const Key('vitals_avpu_A'))), YomaColors.error);
    expect(announced, ['Consciousness missing. Choose a level or tap Not measured.']);
  });

  testWidgets('the first problem is the earliest card on screen, not the last one filled',
      (tester) async {
    await _open(tester);
    await tester.enterText(find.byKey(const Key('vitals_sbp')), '120');
    await tester.enterText(find.byKey(const Key('vitals_dbp')), '80');
    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await tester.pumpAndSettle();
    expect(_cardBorder(tester, find.byKey(const Key('vitals_hr'))), YomaColors.error);
    expect(_cardBorder(tester, find.byKey(const Key('vitals_rr'))), isNot(YomaColors.error));

    // Typing clears the mark.
    await tester.enterText(find.byKey(const Key('vitals_hr')), '80');
    await tester.pump();
    expect(_cardBorder(tester, find.byKey(const Key('vitals_hr'))), isNot(YomaColors.error));
  });
}
