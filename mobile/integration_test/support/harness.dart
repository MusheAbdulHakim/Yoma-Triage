/// Shared by the emulator pass tests. These run on a device against a real backend, and
/// talk to `scripts/run_emulator_pass.py` on the host for what an app can't do itself:
/// airplane mode, killing the backend, screenshots and reading the database.
///
/// The harness is reached over `adb reverse`, so it stays reachable in airplane mode.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:yoma_triage/screens/dispatch_status_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/main.dart' as app;

const registeredCho = '+233240000777';
const unregisteredPhone = '+233240999999';
const compoundName = 'Tamale South CHPS';
const facilityName = 'Tamale Teaching Hospital';
const facilityPhone = '+233240000200';
const motorKingDriver = '+233240000001';
const secondFacilityId = 2;
const backendUrl = 'http://10.0.2.2:8000';

/// Set by the harness for the 320 dp run, which checks layout on every screen it passes.
const smallScreen = bool.fromEnvironment('SMALL_SCREEN');

abstract final class Host {
  static const _base = 'http://127.0.0.1:8765';

  static Future<dynamic> call(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final response = await http
        .get(Uri.parse('$_base$path').replace(queryParameters: query))
        .timeout(const Duration(seconds: 120));
    if (response.statusCode != 200) {
      throw StateError('harness $path: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body);
  }

  static Future<void> airplane(bool on) => call('/airplane', {'on': on ? '1' : '0'});
  static Future<void> killBackend() => call('/backend/kill');
  static Future<void> grantMicrophone() => call('/grant-mic');
  static Future<void> startBackend() => call('/backend/start');
  static Future<void> metric(String name, num value) =>
      call('/metric', {'name': name, 'value': '$value'});
  static Future<void> note(String text) => call('/note', {'text': text});

  static Future<List<Map<String, dynamic>>> rows(String name) async =>
      ((await call('/db', {'q': name})) as List).cast<Map<String, dynamic>>();

  static Future<List<int>> fixture(String name) async {
    final response = await http
        .get(Uri.parse('$_base/fixture/$name'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw StateError('no fixture $name');
    return response.bodyBytes;
  }
}

/// Removes what an earlier run left, so a test starts as a fresh install would.
Future<void> freshInstall() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final docs = await getApplicationDocumentsDirectory();
  final db = File(p.join(docs.path, 'yoma_triage_outbox.db'));
  if (await db.exists()) await db.delete();
}

/// Records every Flutter error, such as a layout overflow, instead of stopping at the
/// first. Without this, a small screen would only ever report its first problem.
class ErrorLog {
  ErrorLog._(this._original);

  final FlutterExceptionHandler? _original;
  final List<String> errors = [];

  static ErrorLog install() {
    final log = ErrorLog._(FlutterError.onError);
    FlutterError.onError = (details) {
      final text = details.exceptionAsString().split('\n').take(2).join(' ');
      // Where in the app, and which screen it happened on.
      final widget = RegExp(r'file:///\S*/lib/\S+').firstMatch(details.toString())?.group(0);
      final titles = find
          .byType(AppBar)
          .evaluate()
          .map((e) => (e.widget as AppBar).title)
          .whereType<Text>()
          .map((t) => t.data);
      // What was taking up the screen when it happened.
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final keyboard = (view.viewInsets.bottom / view.devicePixelRatio).round();
      final banners = find
          .descendant(of: find.byType(Card), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data);
      log.errors.add(
        '$text at ${widget ?? 'unknown'} on ${titles.toList()}; '
        'screen ${(view.physicalSize.height / view.devicePixelRatio).round()} dp high, '
        'keyboard $keyboard dp, banners ${banners.toList()}',
      );
    };
    return log;
  }

  void restore() => FlutterError.onError = _original;

  Future<void> report() async {
    for (final error in errors) {
      await Host.call('/problem', {'text': error});
    }
    expect(errors, isEmpty, reason: errors.join('\n'));
  }
}

Future<void> _recordFailureState(WidgetTester tester) async {
  try {
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();
    await Host.call('/problem', {'text': 'On screen at failure: $texts'});
    await Host.call('/screenshot', {'name': 'failure'});
  } catch (_) {
    // The real failure is the one to report.
  }
}

/// A test that runs the whole app. The handler is restored however the body ends, because
/// the test binding hides the real failure if it isn't.
void flow(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    // Real frames, as a CHO's phone draws them, so timings and animations are realistic.
    IntegrationTestWidgetsFlutterBinding.instance.framePolicy =
        LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final log = ErrorLog.install();
    try {
      await freshInstall();
      await tester.startApp();
      await body(tester);
    } catch (_) {
      await _recordFailureState(tester);
      rethrow;
    } finally {
      log.restore();
    }
    await log.report();
  });
}

extension Drive on WidgetTester {
  /// Live polling, because spinners and timers mean pumpAndSettle would never return.
  Future<void> waitFor(
    Finder finder, {
    Duration timeout = const Duration(seconds: 45),
    String? reason,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) return;
    }
    throw TestFailure('Timed out after $timeout: ${reason ?? finder}');
  }

  /// Real time passes, and the app keeps running.
  Future<void> wait(Duration duration) async {
    final deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      await pump(const Duration(milliseconds: 200));
    }
  }

  /// A tap during the keyboard's animation can miss, so wait for it to close, as a person
  /// would. Only the tap is simulated: the keyboard and layout are real.
  Future<void> closeKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (view.viewInsets.bottom > 0 && DateTime.now().isBefore(deadline)) {
      await pump(const Duration(milliseconds: 100));
    }
    await wait(const Duration(milliseconds: 300));
  }

  /// A list only builds what is near the screen, so on a short phone a widget may not
  /// exist until it is scrolled to.
  Future<void> reveal(Finder finder) async {
    for (final step in const [-300.0, 300.0]) {
      for (var i = 0; i < 25 && finder.evaluate().isEmpty; i++) {
        final lists = find.byType(Scrollable);
        if (lists.evaluate().isEmpty) break;
        await drag(lists.first, Offset(0, step), warnIfMissed: false);
        await wait(const Duration(milliseconds: 150));
      }
    }
    if (finder.evaluate().isEmpty) throw TestFailure('Could not scroll to: $finder');
    await ensureVisible(finder.first);
  }

  Future<void> tapOn(Finder finder) async {
    await closeKeyboard();
    await reveal(finder);
    await wait(const Duration(milliseconds: 300));
    await tap(finder.first);
    await pump(const Duration(milliseconds: 200));
  }

  /// Saves a screenshot, and on the small screen checks that nothing is cut off.
  Future<void> shot(String name) async {
    await pump(const Duration(milliseconds: 400));
    if (smallScreen) await checkLayout(name);
    await Host.call('/screenshot', {'name': name});
  }

  Future<void> checkLayout(String screen) async {
    final width = view.physicalSize.width / view.devicePixelRatio;
    if ((width - 320).abs() > 1) {
      throw TestFailure('Expected a 320 dp wide screen, got $width');
    }
    final buttons = find.byWidgetPredicate(
      (w) =>
          w is ButtonStyleButton ||
          w is IconButton ||
          w is DropdownButtonFormField<String>,
    );
    for (final element in buttons.hitTestable().evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.left < -0.5 || rect.right > width + 0.5) {
        await Host.call('/problem', {
          'text': '$screen: ${element.widget.runtimeType} runs off screen: $rect',
        });
      }
    }
  }

  Future<void> startApp() async {
    // Unmount the running app first. Otherwise Flutter keeps its screens' state, and a
    // restart wouldn't re-read anything a test changed (the catalog's sync time, say).
    await pumpWidget(const SizedBox.shrink());
    app.main();
    await pump();
  }

  Future<void> setUpCho([String phone = registeredCho]) async {
    await waitFor(find.byKey(const Key('setup_phone')));
    // Not enterText: the test tool's keyboard can't reach a field that has lost focus,
    // which happens here when a CHO retries after a refusal.
    widget<TextField>(find.byKey(const Key('setup_phone'))).controller!.text = phone;
    await tapOn(find.text('Continue'));
    await waitFor(find.byKey(const Key('home_emergency_referral')), reason: 'Home after setup');
  }

  Future<void> chooseFacility() async {
    final card = find.textContaining('(tap to confirm facility)');
    await waitFor(card);
    // Wait for the catalog, or the suggested facility shows before it is ready.
    await wait(const Duration(milliseconds: 500));
    await tapOn(card);
    await waitFor(find.text('Choose receiving facility'));
    await tapOn(find.text(facilityName));
    await waitFor(find.textContaining('(confirmed)'));
  }

  Future<void> chooseEmergency([String label = 'Postpartum hemorrhage']) async {
    final field = find.text('Emergency type');
    await tapOn(field);
    await waitFor(find.text(label));
    await tap(find.text(label).last);
    await wait(const Duration(milliseconds: 500));
  }

  Future<void> fillVitals(String prefix) async {
    const values = {
      'sbp': '70',
      'dbp': '40',
      'hr': '130',
      'rr': '32',
      'temp': '38.9',
      'spo2': '88',
    };
    for (final entry in values.entries) {
      final field = find.byKey(Key('${prefix}_${entry.key}'));
      await reveal(field);
      await enterText(field, entry.value);
      await pump(const Duration(milliseconds: 50));
    }
    final avpu = find.byKey(Key('${prefix}_avpu'));
    await tapOn(avpu);
    await wait(const Duration(milliseconds: 500));
    await tap(find.textContaining('Alert').last);
    await wait(const Duration(milliseconds: 500));
  }

  /// From Home, to the Emergency Referral form with facility and type chosen.
  Future<void> openReferralForm() async {
    await tapOn(find.text('Emergency referral'));
    await chooseFacility();
    await chooseEmergency();
  }

  /// From the referral form: open Record vitals from the summary row, fill it, save.
  Future<void> recordVitalsFromForm() async {
    await tapOn(find.byKey(const Key('referral_vitals_summary')));
    await waitFor(find.byKey(const Key('vitals_see_result')));
    await fillVitals('vitals');
    await tapOn(find.byKey(const Key('vitals_see_result')));
    await waitFor(find.byKey(const Key('referral_send')));
  }

  /// The id of the dispatch the status screen is following.
  int dispatchIdOnScreen() =>
      widget<DispatchStatusScreen>(find.byType(DispatchStatusScreen)).dispatchId!;
}

/// A driver's USSD reply, as Africa's Talking would deliver it. Mock SMS, no live traffic.
Future<String> ussd(String phone, String choice) async {
  final response = await http.post(
    Uri.parse('$backendUrl/ussd/callback'),
    body: {
      'sessionId': 'emulator-${DateTime.now().microsecondsSinceEpoch}',
      'serviceCode': '*123#',
      'phoneNumber': phone,
      'text': choice,
    },
  ).timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw StateError('USSD ${response.statusCode}: ${response.body}');
  }
  return response.body;
}

/// The Ref number a driver sees for a dispatch: its referral's id.
Future<int> refOf(int dispatchId) async {
  final row = (await Host.rows('dispatches')).singleWhere((d) => d['id'] == dispatchId);
  return row['referral_id'] as int;
}

/// The code in the hospital's notice, which a hospital must quote to reply.
Future<String> hospitalCode(int dispatchId) async {
  final row = (await Host.rows('dispatches')).singleWhere((d) => d['id'] == dispatchId);
  return row['hospital_code'] as String;
}

/// A driver accepts this dispatch through the USSD menu: 1, the Ref number, then 1.
Future<String> ussdAccept(String phone, int dispatchId) async =>
    ussd(phone, '1*${await refOf(dispatchId)}*1');

/// A driver confirms arrival for their trip: 2, then 1.
Future<String> ussdArrival(String phone) => ussd(phone, '2*1');

/// A hospital's SMS reply, as Africa's Talking would deliver it.
Future<Map<String, dynamic>> hospitalReply(String phone, String text) async {
  final response = await http.post(
    Uri.parse('$backendUrl/api/v1/sms/inbound'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'from': phone, 'text': text}),
  ).timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw StateError('SMS ${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}
