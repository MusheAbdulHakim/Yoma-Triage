import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  static String get baseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    return 'http://10.0.2.2:8000'; // Android emulator → host
  }
}

/// Seed-aligned facility labels (ids 1 / 1).
abstract final class FacilityConfig {
  static const chpsCompoundId = 1;
  static const chpsLabel = 'Tamale South CHPS';
  static const facilityId = 1;
  static const facilityLabel = 'Tamale Teaching Hospital';
}
