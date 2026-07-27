import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';
import 'package:yoma_triage/widgets/breathing_pulse.dart';

void main() {
  testWidgets('BreathingPulse paints rings while active', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomaTheme(),
        home: const Scaffold(
          body: BreathingPulse(
            active: true,
            child: Text('15'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('breathing_pulse')), findsOneWidget);
    expect(find.byKey(const Key('breathing_pulse_rings')), findsOneWidget);
    expect(find.text('15'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('breathing_pulse_rings')), findsOneWidget);
  });

  testWidgets('BreathingPulse hides rings when inactive', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildYomaTheme(),
        home: const Scaffold(
          body: BreathingPulse(
            active: false,
            child: Text('done'),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('breathing_pulse')), findsOneWidget);
    expect(find.byKey(const Key('breathing_pulse_rings')), findsNothing);
    expect(find.text('done'), findsOneWidget);
  });
}
