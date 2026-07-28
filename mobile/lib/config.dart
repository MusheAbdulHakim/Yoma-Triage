import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Backend API base URL for the CHO app (Android, iOS, and web).
///
/// Prefer `--dart-define=API_BASE_URL=...` for physical devices and tunnels.
/// Defaults:
/// - Web → loopback
/// - iOS Simulator → loopback (shares the Mac network stack)
/// - Android emulator → `10.0.2.2` (host loopback alias)
class ApiConfig {
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'http://127.0.0.1:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}

/// Breath-sound screening capture length (seconds).
///
/// Set in repo-root `.env` as `SCREENING_DURATION_SEC`, then pass at run time:
/// `--dart-define=SCREENING_DURATION_SEC=$SCREENING_DURATION_SEC`
/// Defaults to 15 when unset or invalid.
abstract final class ScreeningConfig {
  static const int defaultDurationSec = 15;

  static int get durationSec {
    const raw = String.fromEnvironment('SCREENING_DURATION_SEC');
    if (raw.isEmpty) return defaultDurationSec;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) return defaultDurationSec;
    return parsed;
  }
}

/// Seed-aligned facility labels (ids 1 / 1).
/// Prefer on-device catalog + picker in production journeys.
abstract final class FacilityConfig {
  static const chpsCompoundId = 1;
  static const chpsLabel = 'Tamale South CHPS';
  static const facilityId = 1;
  static const facilityLabel = 'Tamale Teaching Hospital';
  static const homeChpsPrefsKey = 'home_chps_compound_id';
}
