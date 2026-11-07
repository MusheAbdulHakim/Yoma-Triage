// A3: release builds fail closed. The rules are checked by Gradle at build time and by
// the app at startup; these tests cover the app's copy and keep the two in step.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/release_settings.dart';

List<String> _check({
  String appEnv = 'production',
  String apiBaseUrl = 'https://api.yomatriage.gh',
  String apiKey = 'key',
  bool testRelease = false,
}) =>
    releaseSettingsProblems(
      appEnv: appEnv,
      apiBaseUrl: apiBaseUrl,
      apiKey: apiKey,
      testRelease: testRelease,
    );

void main() {
  group('release settings', () {
    test('production with an HTTPS server and a key is accepted', () {
      expect(_check(), isEmpty);
    });

    test('anything but production is refused', () {
      for (final env in ['', 'development', 'staging', 'Production']) {
        expect(_check(appEnv: env), [contains('APP_ENV must be production')], reason: env);
      }
    });

    test('no server, or plain http, is refused', () {
      for (final url in ['', 'http://api.yomatriage.gh', 'api.yomatriage.gh', 'https://']) {
        expect(_check(apiBaseUrl: url), [contains('https://')], reason: url);
      }
    });

    test('this computer or the emulator is refused, even over https', () {
      for (final url in [
        'https://10.0.2.2:8000',
        'https://localhost',
        'https://127.0.0.1',
        'https://0.0.0.0',
      ]) {
        expect(_check(apiBaseUrl: url), [contains('must not point at')], reason: url);
      }
    });

    test('a missing API key is refused', () {
      expect(_check(apiKey: '  '), ['API_KEY must be set']);
    });

    test('every problem is listed, not just the first', () {
      expect(_check(appEnv: 'development', apiBaseUrl: 'http://10.0.2.2:8000', apiKey: ''),
          hasLength(3));
    });

    test('a test release may use the emulator over http', () {
      expect(
        _check(appEnv: 'development', apiBaseUrl: 'http://10.0.2.2:8000', apiKey: '',
            testRelease: true),
        isEmpty,
      );
    });

    test('a test release can never be a production build', () {
      expect(_check(testRelease: true), [contains("can't be combined")]);
    });

    test('debug and test runs are never refused', () {
      expect(currentReleaseProblems(), isEmpty);
    });

    test('Gradle checks the same hosts and settings', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('val localHosts = setOf("localhost", "127.0.0.1", "10.0.2.2", '
          '"0.0.0.0")'));
      for (final key in ['APP_ENV', 'API_BASE_URL', 'API_KEY', 'YOMA_TEST_RELEASE']) {
        expect(gradle, contains('defines["$key"]'), reason: key);
      }
      expect(gradle, contains('dependsOn(checkReleaseSettings)'));
    });
  });

  testWidgets('a wrongly built release says so, and how to get help', (tester) async {
    await tester.pumpWidget(const MisconfiguredBuildApp(problems: ['APP_ENV must be production']));
    expect(find.byKey(const Key('misconfigured_build')), findsOneWidget);
    expect(find.textContaining('phone the driver'), findsOneWidget);
    expect(find.text('• APP_ENV must be production'), findsOneWidget);
  });

  testWidgets('a test release is labelled on every screen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(builder: testReleaseBanner, home: Scaffold(body: Text('Home'))),
    );
    expect(find.byKey(const Key('test_release_banner')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        builder: testReleaseBanner,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Next'))),
            ),
            child: const Text('Go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    expect(find.byKey(const Key('test_release_banner')), findsOneWidget);
  });
}
