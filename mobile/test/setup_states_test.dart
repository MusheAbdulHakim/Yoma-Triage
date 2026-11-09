import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/screens/setup_screen.dart';
import 'package:yoma_triage/services/api_client.dart';
import 'package:yoma_triage/services/cho_store.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';
import 'package:yoma_triage/widgets/dispatch_timeline_view.dart' show NavyHelpCard;

/// Round 7: first-run setup as three separate states.
class _Api extends ApiClient {
  _Api({this.error});

  final Object? error;
  String? lookedUp;

  @override
  Future<Map<String, dynamic>> lookupCho(String phone) async {
    lookedUp = phone;
    if (error != null) throw error!;
    return {
      'name': 'Abena Mensah',
      'phone': phone,
      'compound_id': 7,
      'compound_name': 'Tamale South CHPS',
    };
  }

  @override
  Future<Map<String, dynamic>> getCompoundContacts(int compoundId) async =>
      {'compound_id': compoundId, 'drivers': [], 'facilities': []};
}

Future<void> _open(WidgetTester tester, ApiClient api,
    {ValueChanged<ChoIdentity>? onComplete,
    Size size = const Size(360, 640),
    double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildYomaTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: SetupScreen(api: api, onComplete: onComplete ?? (_) {}),
  ));
  // The notice and the local queue load in real time.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

VoidCallback? _continue(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('setup_continue'))).onPressed;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('setup_phone')), text);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('+233 is shown, the placeholder is neutral, and the keypad is numeric',
      (tester) async {
    await _open(tester, _Api());
    expect(find.text('+233'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('setup_phone')));
    expect(field.keyboardType, TextInputType.number);
    expect(field.decoration!.hintText, isNull, reason: 'no real-looking example number');
    expect(field.controller!.text, isEmpty);
    expect(find.textContaining(RegExp(r'\d{2} \d{3} \d{4}')), findsNothing);
  });

  testWidgets('Continue stays disabled until the number is complete', (tester) async {
    await _open(tester, _Api());
    expect(_continue(tester), isNull, reason: 'empty');
    await _type(tester, '24000070');
    expect(_continue(tester), isNull, reason: '8 digits');
    await _type(tester, '240000700');
    expect(_continue(tester), isNotNull, reason: '9 digits after +233');
    await _type(tester, '0240000700');
    expect(_continue(tester), isNotNull, reason: 'with the leading 0');
    await _type(tester, '024000070');
    expect(_continue(tester), isNull, reason: '0 and only 8 more digits');
    await _type(tester, '24abc0000700');
    expect(tester.widget<TextField>(find.byKey(const Key('setup_phone'))).controller!.text,
        '240000700',
        reason: 'digits only');
  });

  testWidgets('confirmed: check icon, the clinic from the server, and Start', (tester) async {
    final api = _Api();
    ChoIdentity? started;
    await _open(tester, api, onComplete: (i) => started = i);
    await _type(tester, '240000700');
    await tester.tap(find.byKey(const Key('setup_continue')));
    await tester.pumpAndSettle();

    expect(api.lookedUp, '+233240000700');
    expect(find.byKey(const Key('setup_confirmed')), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('Tamale South CHPS'), findsOneWidget);
    expect(find.byKey(const Key('setup_phone')), findsNothing, reason: 'its own state');
    expect(started, isNull, reason: 'nothing happens before Start');
    expect(await ChoStore().load(), isNull, reason: 'saved only on Start');

    await tester.tap(find.byKey(const Key('setup_start')));
    await tester.pumpAndSettle();
    expect(started!.compoundName, 'Tamale South CHPS');
    expect((await ChoStore().load())!.compoundId, 7);
  });

  testWidgets('Not your clinic? goes back to the number', (tester) async {
    await _open(tester, _Api());
    await _type(tester, '240000700');
    await tester.tap(find.byKey(const Key('setup_continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setup_change_number')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setup_phone')), findsOneWidget);
    expect(await ChoStore().load(), isNull);
  });

  for (final (name, error, message) in [
    (
      'not registered',
      ApiException(404, '{"detail":"x","code":"CHO_NOT_REGISTERED"}'),
      "This number isn't registered. Ask your district coordinator.",
    ),
    (
      'network error',
      Exception('no route'),
      "Can't reach the server. Check your signal and try again.",
    ),
  ]) {
    testWidgets('$name: alert icon on the dark navy strip, not red', (tester) async {
      await _open(tester, _Api(error: error));
      await _type(tester, '240000700');
      await tester.tap(find.byKey(const Key('setup_continue')));
      await tester.pumpAndSettle();
      final strip = find.byKey(const Key('setup_error'));
      expect(tester.widget(strip), isA<NavyHelpCard>());
      expect(find.descendant(of: strip, matching: find.text(message)), findsOneWidget);
      expect(find.descendant(of: strip, matching: find.byIcon(Icons.warning_amber_rounded)),
          findsOneWidget);
      final box = tester
          .widget<Container>(find.descendant(of: strip, matching: find.byType(Container)).first);
      expect((box.decoration! as BoxDecoration).color, YomaColors.navy);
    });
  }

  testWidgets('deactivated or moved: the re-setup notice uses the same navy strip', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChoStore.noticePrefsKey: 'You have been moved to Savelugu CHPS. Confirm your number '
          'to set up this phone for your new compound.',
    });
    await _open(tester, _Api());
    for (var i = 0; i < 100 && find.byKey(const Key('setup_notice')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(tester.widget(find.byKey(const Key('setup_notice'))), isA<NavyHelpCard>());
    expect(find.textContaining('moved to Savelugu CHPS'), findsOneWidget);
  });

  testWidgets('the keyboard never hides the phone field or Continue', (tester) async {
    await _open(tester, _Api());
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final visible = 640 - 300.0;
    expect(tester.getRect(find.byKey(const Key('setup_phone'))).bottom, lessThanOrEqualTo(visible));
    expect(
        tester.getRect(find.byKey(const Key('setup_continue'))).bottom, lessThanOrEqualTo(visible));
  });

  testWidgets('320 dp and 130% text: everything fits and Continue is reachable', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChoStore.noticePrefsKey: 'This CHO is no longer active. Ask your district coordinator '
          'to reactivate it.',
    });
    await _open(tester, _Api(), size: const Size(320, 568), scale: 1.3);
    expect(tester.takeException(), isNull);
    await _type(tester, '240000700');
    await tester.ensureVisible(find.byKey(const Key('setup_continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setup_continue')).hitTestable(), findsOneWidget);
  });
}
