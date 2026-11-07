import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;

import 'parameters.dart';

/// Backend API base URL for the CHO app (Android, iOS, and web).
///
/// Prefer `--dart-define=API_BASE_URL=...` for physical devices and tunnels.
/// Defaults:
/// - Web → loopback
/// - iOS Simulator → loopback (shares the Mac network stack)
/// - Android emulator → `10.0.2.2` (host loopback alias)
/// - Release builds → none: `API_BASE_URL` must be given (see release_settings.dart)
class ApiConfig {
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // No development defaults in a release: it must say where its server is, and
    // release_settings.dart refuses to start one that doesn't.
    if (kReleaseMode) return '';
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'http://127.0.0.1:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  /// Optional shared secret for CHO API routes (`X-API-Key`).
  /// Pass `--dart-define=API_KEY=...` when the backend has `API_KEY` set.
  static String get apiKey {
    const raw = String.fromEnvironment('API_KEY', defaultValue: '');
    return raw.trim();
  }
}

/// Breath-sound screening capture length (seconds).
///
/// Set in repo-root `.env` as `SCREENING_DURATION_SEC`, then pass at run time:
/// `--dart-define=SCREENING_DURATION_SEC=$SCREENING_DURATION_SEC`
/// Uses the default in `parameters.dart` when unset or invalid.
abstract final class ScreeningConfig {
  static const int defaultDurationSec = Parameters.defaultScreeningSeconds;

  static int get durationSec {
    const raw = String.fromEnvironment('SCREENING_DURATION_SEC');
    if (raw.isEmpty) return defaultDurationSec;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) return defaultDurationSec;
    return parsed;
  }

  /// `yamnet` | `hear_event` | `opera_ce` | `stub`
  /// Pass `--dart-define=SCREENING_MODEL=...`
  static String get model {
    const raw = String.fromEnvironment('SCREENING_MODEL', defaultValue: 'yamnet');
    final v = raw.trim().toLowerCase();
    const allowed = {'yamnet', 'hear_event', 'opera_ce', 'stub'};
    return allowed.contains(v) ? v : 'yamnet';
  }

  /// Acoustic screening is off and hidden unless explicitly enabled with
  /// `--dart-define=MOEWS_ONLY=false`. Any other value keeps it off.
  static bool get moewsOnly {
    const raw = String.fromEnvironment('MOEWS_ONLY', defaultValue: 'true');
    return !(raw.toLowerCase() == 'false' || raw == '0');
  }

  /// When true and primary model is hear_event/opera_ce, also run YAMNet for ops compare.
  /// Scores-only telemetry; does not change CTA (primary model wins).
  static bool get dualRunYamnet {
    const raw = String.fromEnvironment('SCREENING_DUAL_RUN', defaultValue: 'false');
    return raw.toLowerCase() == 'true' || raw == '1';
  }
}

/// App deploy flavour (documentation + banners). Not a secret.
abstract final class AppEnvironment {
  /// `development` | `staging` | `production`
  static String get name {
    const raw = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    final v = raw.trim().toLowerCase();
    if (v == 'staging' || v == 'production' || v == 'development') return v;
    return 'development';
  }

  static bool get isProduction => name == 'production';
}

/// Seed-aligned facility label, shown only until the catalog has loaded.
abstract final class FacilityConfig {
  static const facilityId = 1;
  static const facilityLabel = 'Tamale Teaching Hospital';
}

/// Catalog freshness (days). Banner when older.
abstract final class CatalogConfig {
  static const staleAfterDays = Parameters.catalogStaleAfterDays;
  static const syncedAtPrefsKey = 'catalog_synced_at';
  static const catalogVersionPrefsKey = 'catalog_version';
}
