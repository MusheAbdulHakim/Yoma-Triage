import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

/// A3: a release build fails closed.
///
/// A release must carry production settings and an HTTPS server address, or be marked as
/// a test build with `--dart-define=YOMA_TEST_RELEASE=true`, which is labelled on every
/// screen. android/app/build.gradle.kts refuses to build anything else; this checks the
/// same rules again at startup, so a build that slipped through refuses to run.

/// Set only by test release builds, such as the emulator pass.
const bool yomaTestRelease = bool.fromEnvironment('YOMA_TEST_RELEASE');

const _localHosts = {'localhost', '127.0.0.1', '10.0.2.2', '0.0.0.0'};

/// What's wrong with these settings for a release build. Empty means they're fine.
List<String> releaseSettingsProblems({
  required String appEnv,
  required String apiBaseUrl,
  required String apiKey,
  required bool testRelease,
}) {
  final env = appEnv.trim();
  if (testRelease) {
    return env == 'production'
        ? ["YOMA_TEST_RELEASE=true can't be combined with APP_ENV=production"]
        : const [];
  }
  final problems = <String>[];
  if (env != 'production') problems.add("APP_ENV must be production (got '$env')");
  final url = apiBaseUrl.trim();
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (!url.startsWith('https://') || host.isEmpty) {
    problems.add("API_BASE_URL must be an https:// address (got '$url')");
  } else if (_localHosts.contains(host)) {
    problems.add("API_BASE_URL must not point at this computer or the emulator (got '$url')");
  }
  if (apiKey.trim().isEmpty) problems.add('API_KEY must be set');
  return problems;
}

/// This build's problems, or empty outside release builds.
List<String> currentReleaseProblems() {
  if (!kReleaseMode) return const [];
  return releaseSettingsProblems(
    appEnv: const String.fromEnvironment('APP_ENV'),
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
    apiKey: const String.fromEnvironment('API_KEY'),
    testRelease: yomaTestRelease,
  );
}

/// Shown instead of the app when a release was built without the settings it needs.
class MisconfiguredBuildApp extends StatelessWidget {
  const MisconfiguredBuildApp({super.key, required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.block, size: 64, color: Color(0xFFC62828)),
              const SizedBox(height: 16),
              const Text(
                'This copy of Yoma Triage was built wrongly and cannot be used.',
                key: Key('misconfigured_build'),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                'It would not be able to send referrals. For an emergency, phone the driver '
                'and the hospital directly. Ask your district coordinator for a corrected '
                'app.',
                style: TextStyle(fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              const Text('For the person who built it:',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              for (final problem in problems) Text('• $problem'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps every screen of a test release in a red label, so it can't be mistaken for the
/// real app.
Widget testReleaseBanner(BuildContext context, Widget? child) {
  return Column(
    children: [
      Material(
        color: const Color(0xFFC62828),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'TEST BUILD — not for patient use',
                key: const Key('test_release_banner'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        // Its own semantics boundary: a route blocks the semantics of whatever was painted
        // before it within the same boundary, which would hide the label from TalkBack.
        child: Semantics(
          container: true,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ],
  );
}
