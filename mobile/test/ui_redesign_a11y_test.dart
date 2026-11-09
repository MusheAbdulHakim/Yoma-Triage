// UI redesign round 1, step 4: accessibility of the redesigned screens.
//
// - Tap targets at least 48 dp, and every tap target labelled (Flutter's guidelines).
// - Text contrast, measured on the rendered screen and on the colour tokens.
// - 130% text on a 320 dp-wide screen: no overflow.
// - The risk level is announced in words.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:yoma_triage/screens/home_screen.dart';
import 'package:yoma_triage/screens/queued_referral_screen.dart';
import 'package:yoma_triage/screens/referral_screen.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/offline_queue.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/screening_service.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

import 'helpers/cho_helper.dart';

ApiClient _offline() => ApiClient(
      client: MockClient((_) async => throw http.ClientException('no signal')),
      baseUrl: 'http://test.invalid',
    );

class _Queue extends OfflineQueue {
  _Queue({this.failedN = 0, this.staleN = 0, this.expiringN = 0}) {
    needsConfirmationCount.value = staleN;
  }

  final int failedN;
  final int staleN;
  final int expiringN;

  @override
  Future<List<QueuedReferral>> failed() async {
    failedCount.value = failedN;
    return const [];
  }

  @override
  Future<List<QueuedReferral>> needsConfirmation() async {
    needsConfirmationCount.value = staleN;
    return const [];
  }

  @override
  Future<int> noteExpiryWarning({DateTime? now}) async {
    expiringCount.value = expiringN;
    return expiringN;
  }
}

Map<String, Object?> _vitals({int sbp = 120, int hr = 80, int? spo2 = 98, String? avpu = 'A'}) => {
      'systolic_bp': sbp,
      'diastolic_bp': 80,
      'heart_rate': hr,
      'respiratory_rate': 18,
      'temperature': 37.0,
      'spo2': spo2,
      'consciousness_level': avpu,
    };

ResultScreen _result(Map<String, Object?> v) => ResultScreen(
      result: moewsOnlyResult(),
      vitals: v,
      moews: calculateMoews(
        sbp: v['systolic_bp'] as int?,
        dbp: v['diastolic_bp'] as int?,
        hr: v['heart_rate'] as int?,
        rr: v['respiratory_rate'] as int?,
        temp: v['temperature'] as double?,
        spo2: v['spo2'] as int?,
        consciousness: v['consciousness_level'] as String?,
      ),
    );

/// A breathing check that records nothing; it can fail to start.
class _Breathing extends ScreeningService {
  _Breathing({this.failStart});

  final Object? failStart;

  @override
  Future<void> startRecording() async {
    if (failStart != null) throw failStart!;
  }

  @override
  Stream<double> microphoneLevels() => const Stream.empty();

  @override
  Future<ScreeningResult> stopAndClassify() async => unavailableResult();

  @override
  Future<void> dispose() async {}
}

ScreeningResult _acoustic(String label) => ScreeningResult(
      label: label,
      confidence: 0.7,
      reason: 'test',
      source: 'yamnet',
      modelVersion: 'test',
    );

/// A dispatch that always reports [status].
class _Dispatch extends ApiClient {
  _Dispatch(this.status, {this.driver, this.divertedFrom});

  final String status;
  final String? driver;
  final String? divertedFrom;

  @override
  Future<Map<String, dynamic>> getDispatch(int id) async => {
        'id': id,
        'referral_id': 4821,
        'facility_id': 1,
        'facility_name': 'Tamale Teaching Hospital',
        'diverted_from': divertedFrom,
        'driver_name': driver,
        'status': status,
        'current_tier': 1,
      };
}

Widget _dispatchScreen(String status, {String? driver, String? divertedFrom}) =>
    DispatchStatusScreen(
      dispatchId: 9,
      clientRequestId: 'req-1',
      facilityId: 1,
      api: _Dispatch(status, driver: driver, divertedFrom: divertedFrom),
      launcher: (_) async => true,
    );

/// Every redesigned screen, in the states that matter.
final Map<String, Widget Function()> _screens = {
  'Home (MOEWS-only, every warning)': () => HomeScreen(
        api: _offline(),
        acousticEnabled: false,
        queue: _Queue(failedN: 2, staleN: 1, expiringN: 3)
          ..noteRetryWarning('Could not send. Will retry when there is signal.'),
      ),
  'Home (acoustic)': () =>
      HomeScreen(api: _offline(), acousticEnabled: true, queue: _Queue(expiringN: 1)),
  'Record vitals': () => VitalsScreen(result: moewsOnlyResult()),
  'Result RED': () => _result(_vitals(sbp: 185, hr: 118)),
  'Result AMBER': () => _result(_vitals(hr: 118)),
  'Result GREEN': () => _result(_vitals(spo2: null)),
  'Result INCOMPLETE': () => _result(_vitals(avpu: null)),
  'Emergency referral form': () => ReferralScreen(api: _offline()),
  // Round 2: the breathing check.
  'Breathing: Ready': () =>
      ScreeningScreen(forceWebSimulator: false, service: _Breathing(), showReadyStep: true),
  'Breathing: Recording': () => ScreeningScreen(forceWebSimulator: false, service: _Breathing()),
  'Breathing: Microphone blocked': () => ScreeningScreen(
        forceWebSimulator: false,
        service: _Breathing(failStart: StateError('Microphone permission denied')),
      ),
  // Round 3: dispatch status and the not-sent-yet screen.
  'Dispatch: waiting for drivers': () => _dispatchScreen('TIER1_NOTIFIED'),
  'Dispatch: driver accepted': () => _dispatchScreen('HOSPITAL_NOTIFIED', driver: 'Ibrahim'),
  'Dispatch: no driver': () => _dispatchScreen('FAILED'),
  'Dispatch: diverted': () => _dispatchScreen('HOSPITAL_NOTIFIED',
      driver: 'Ibrahim', divertedFrom: 'Navrongo War Memorial Hospital'),
  'Not sent yet': () =>
      QueuedReferralScreen(clientRequestId: 'req-1', facilityId: 1, launcher: (_) async => true),
  'Result with breathing advisory': () => ResultScreen(
        result: _acoustic('RED'),
        vitals: _vitals(hr: 118),
        moews: calculateMoews(
            sbp: 120, dbp: 80, hr: 118, rr: 18, temp: 37.0, spo2: 98, consciousness: 'A'),
      ),
};

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, Widget screen, {double textScale = 1.0}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: screen,
  ));
  // Identity, catalog and counts load asynchronously.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _luminance(Color c) => c.computeLuminance();

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Every node in the live semantics tree: what TalkBack actually gets.
List<SemanticsNode> semanticsNodes(WidgetTester tester) {
  final root = tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  final out = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    out.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return out;
}

/// Stronger than Flutter's labeled-tap-target guideline, which skips any node flagged as
/// a text field (so a toggle merged into a field, or an unnamed field, passes it).
void expectSeparateNamedControls(WidgetTester tester) {
  for (final node in semanticsNodes(tester)) {
    if (node.isInvisible || node.isMergedIntoParent) continue;
    final flags = node.flagsCollection;
    final data = node.getSemanticsData();
    final label = data.label.trim();
    expect(flags.isTextField && flags.isButton, isFalse,
        reason: 'a button merged into a text field: $node');
    expect(flags.isTextField && data.hasAction(SemanticsAction.tap) && label.isEmpty, isFalse,
        reason: 'an editable field with no name: $node');
    if (!flags.isTextField && data.hasAction(SemanticsAction.tap)) {
      expect(label.isNotEmpty || data.tooltip.isNotEmpty, isTrue,
          reason: 'a tappable control with no name: $node');
    }
  }
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues(registeredChoPrefs());
  });

  for (final entry in _screens.entries) {
    group(entry.key, () {
      testWidgets('tap targets are at least 48 dp and labelled', (tester) async {
        _screen(tester, const Size(360, 640));
        final handle = tester.ensureSemantics();
        await _pump(tester, entry.value());
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('every control is its own named node in the semantics tree', (tester) async {
        _screen(tester, const Size(360, 640));
        final handle = tester.ensureSemantics();
        await _pump(tester, entry.value());
        expectSeparateNamedControls(tester);
        handle.dispose();
      });

      testWidgets('text meets WCAG AA contrast as rendered', (tester) async {
        _screen(tester, const Size(360, 640));
        final handle = tester.ensureSemantics();
        await _pump(tester, entry.value());
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      for (final size in const [Size(320, 568), Size(360, 640)]) {
        testWidgets('130% text at ${size.width.toInt()} dp: no overflow or clipping',
            (tester) async {
          _screen(tester, size);
          await _pump(tester, entry.value(), textScale: 1.3);
          expect(tester.takeException(), isNull);
          // Scroll through everything that scrolls; nothing may overflow on the way.
          final count = find.byType(Scrollable).evaluate().length;
          for (var i = 0; i < count; i++) {
            // Found afresh each time: scrolling rebuilds what is inside.
            final elements = find.byType(Scrollable).evaluate().toList();
            if (i >= elements.length || !elements[i].mounted) continue;
            final state = (elements[i] as StatefulElement).state as ScrollableState;
            if (state.position.axis != Axis.vertical) continue;
            state.position.jumpTo(state.position.maxScrollExtent);
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
        });
      }
    });
  }

  group('risk level is announced in words', () {
    for (final (name, vitals, word) in [
      ('RED', _vitals(sbp: 185), 'Critical'),
      ('AMBER', _vitals(hr: 118), 'Elevated'),
      ('GREEN', _vitals(), 'Stable'),
      ('INCOMPLETE', _vitals(avpu: null), 'Incomplete'),
    ]) {
      testWidgets(name, (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, _result(vitals));
        expect(
          find.bySemanticsLabel(RegExp('^Risk level: $word\\.')),
          findsOneWidget,
        );
        handle.dispose();
      });
    }
  });

  test('every token colour pair used on the redesigned screens meets WCAG AA', () {
    const w = Colors.white;
    // (description, foreground, background, large text?)
    final pairs = <(String, Color, Color, bool)>[
      ('emergency label on teal', w, YomaColors.brand, true),
      ('teal text on white', YomaColors.brand, YomaColors.surface, false),
      ('teal text on canvas', YomaColors.brand, YomaColors.canvas, false),
      ('white on teal (chips, buttons)', w, YomaColors.brand, false),
      ('white on navy strip', w, YomaColors.navy, false),
      ('navy strip subtitle', const Color(0xFFDCE3EC), YomaColors.navy, false),
      ('grey900 on canvas', YomaColors.grey900, YomaColors.canvas, false),
      ('grey800 on white', YomaColors.grey800, YomaColors.surface, false),
      ('grey700 on grey100', YomaColors.grey700, YomaColors.grey100, false),
      ('grey700 on grey200', YomaColors.grey700, YomaColors.grey200, false),
      ('grey600 on white', YomaColors.grey600, YomaColors.surface, false),
      ('grey600 on canvas', YomaColors.grey600, YomaColors.canvas, false),
      ('grey600 on grey100', YomaColors.grey600, YomaColors.grey100, false),
      ('disabled button grey600 on grey200', YomaColors.grey600, YomaColors.grey200, true),
      ('placeholder grey500 on canvas (20 sp bold)', YomaColors.grey500, YomaColors.canvas, true),
      ('error on white', YomaColors.error, YomaColors.surface, false),
      ('warning on canvas', YomaColors.warning, YomaColors.canvas, false),
      ('white on RED', TriageColors.onRed, TriageColors.red, false),
      ('grey900 on AMBER', TriageColors.onAmber, TriageColors.amber, false),
      ('white on GREEN', TriageColors.onGreen, TriageColors.green, false),
      ('grey900 on incomplete grey', TriageColors.onIncomplete, TriageColors.incompleteFill, false),
    ];
    for (final (name, fg, bg, large) in pairs) {
      final ratio = contrast(fg, bg);
      expect(ratio, greaterThanOrEqualTo(large ? 3.0 : 4.5),
          reason: '$name: ${ratio.toStringAsFixed(2)}:1');
    }
  });

  testWidgets('Record vitals: six named editable fields and seven separate toggles',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final handle = tester.ensureSemantics();
    await _pump(tester, VitalsScreen(result: moewsOnlyResult()));
    final nodes = semanticsNodes(tester).where((n) => !n.isMergedIntoParent).toList();
    final fields = nodes.where((n) => n.flagsCollection.isTextField).map((n) => n.label).toList();
    expect(fields.length, 6, reason: '$fields');
    for (final name in [
      'Systolic blood pressure',
      'Diastolic blood pressure',
      'Heart rate',
      'Breathing rate',
      'Temperature',
      'Oxygen saturation',
    ]) {
      expect(fields.where((l) => l.startsWith(name)), hasLength(1), reason: name);
    }
    final toggles = nodes
        .where((n) => n.flagsCollection.isButton && n.label.endsWith('not measured'))
        .map((n) => n.label)
        .toList();
    expect(toggles, hasLength(7), reason: '$toggles');
    expect(toggles, contains('Heart rate not measured'));
    expect(toggles, contains('Consciousness not measured'));
    handle.dispose();
  });

  testWidgets('Record vitals: a validation message is shown whole, below the field',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester, VitalsScreen(result: moewsOnlyResult()));
    await tester.tap(find.byKey(const Key('vitals_see_result')));
    await tester.pump();
    final error = find.byKey(const Key('vitals_hr_error'));
    expect(error, findsOneWidget);
    final field = tester.getRect(find.byKey(const Key('vitals_hr')));
    final message = tester.getRect(error);
    expect(message.top, greaterThanOrEqualTo(field.bottom), reason: 'below the field');
    expect(message.width, greaterThan(field.width * 2), reason: 'full card width');
    final painter = tester
        .renderObject<RenderParagraph>(find.descendant(of: error, matching: find.byType(RichText)));
    expect(painter.didExceedMaxLines, isFalse, reason: 'never cut off');
  });
}
