import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/widgets/yoma_components.dart';

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

/// Picks a consciousness level by its old dropdown label ('A — Alert', 'Not measured'),
/// which is now a chip.
Future<void> selectAvpu(
  WidgetTester tester, {
  String prefix = 'vitals',
  String avpu = 'A — Alert',
}) async {
  final id = avpu == 'Not measured' ? 'not_measured' : avpu.substring(0, 1);
  final chip = find.byKey(Key('${prefix}_avpu_$id'));
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// True when the field's toggle offers Clear, i.e. it is marked not measured.
bool markedNotMeasured(String toggleKey) => find
    .descendant(of: find.byKey(Key(toggleKey)), matching: find.text('Clear'))
    .evaluate()
    .isNotEmpty;

/// No consciousness chip is selected.
void expectNoAvpuSelected(WidgetTester tester, String prefix) {
  for (final code in const ['A', 'V', 'P', 'U']) {
    final chip = tester.widget<YomaChoiceChip>(find.byKey(Key('${prefix}_avpu_$code')));
    expect(chip.selected, isFalse, reason: code);
  }
  expect(markedNotMeasured('${prefix}_avpu_not_measured'), isFalse);
}
