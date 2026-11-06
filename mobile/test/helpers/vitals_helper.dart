import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gives the long vitals forms room so every field is built and tappable.
void useTallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Fills the vitals form with normal adult values unless overridden.
Future<void> fillVitals(
  WidgetTester tester, {
  String prefix = 'vitals',
  Map<String, String> overrides = const {},
  String avpu = 'A — Alert',
}) async {
  const normal = {
    'sbp': '120',
    'dbp': '80',
    'hr': '80',
    'rr': '18',
    'temp': '37.0',
    'spo2': '98',
  };
  for (final entry in {...normal, ...overrides}.entries) {
    await tester.enterText(
      find.byKey(Key('${prefix}_${entry.key}')),
      entry.value,
    );
  }
  await selectAvpu(tester, prefix: prefix, avpu: avpu);
}

Future<void> selectAvpu(
  WidgetTester tester, {
  String prefix = 'vitals',
  String avpu = 'A — Alert',
}) async {
  await tester.tap(find.byKey(Key('${prefix}_avpu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(avpu).last);
  await tester.pumpAndSettle();
}
