import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'cho_store.dart';

class CachedDriver {
  const CachedDriver({
    required this.name,
    required this.phone,
    required this.isMotorKing,
  });

  final String name;
  final String phone;
  final bool isMotorKing;
}

class CachedFacility {
  const CachedFacility({
    required this.id,
    required this.name,
    required this.phone,
  });

  final int id;
  final String name;
  final String phone;
}

class CachedContacts {
  const CachedContacts({
    required this.drivers,
    required this.facilities,
    required this.updatedAt,
  });

  final List<CachedDriver> drivers;
  final List<CachedFacility> facilities;
  final DateTime updatedAt;

  factory CachedContacts.fromJson(Map<String, dynamic> json, DateTime updatedAt) {
    return CachedContacts(
      drivers: [
        for (final d in json['drivers'] as List)
          CachedDriver(
            name: d['name'] as String,
            phone: d['phone'] as String,
            isMotorKing: d['is_motor_king'] as bool,
          ),
      ],
      facilities: [
        for (final f in json['facilities'] as List)
          CachedFacility(
            id: (f['id'] as num).toInt(),
            name: f['name'] as String,
            phone: f['phone'] as String,
          ),
      ],
      updatedAt: updatedAt,
    );
  }
}

/// The compound's drivers and the facilities' phones, saved for when the network is
/// gone. A failed refresh never touches what is already saved.
class ContactsStore {
  static const prefsKey = 'manual_contacts';
  static const updatedAtPrefsKey = 'manual_contacts_updated_at';

  Future<CachedContacts?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    final updatedAt = DateTime.tryParse(prefs.getString(updatedAtPrefsKey) ?? '');
    if (raw == null || updatedAt == null) return null;
    try {
      return CachedContacts.fromJson(jsonDecode(raw) as Map<String, dynamic>, updatedAt);
    } catch (_) {
      return null;
    }
  }

  /// Best effort; never throws. Returns whether the saved list was updated.
  Future<bool> refresh(ApiClient api, int compoundId) async {
    try {
      final body = await api.getCompoundContacts(compoundId);
      // Parse first, so a malformed reply can't replace a good list.
      final now = DateTime.now().toUtc();
      CachedContacts.fromJson(body, now);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(body));
      await prefs.setString(updatedAtPrefsKey, now.toIso8601String());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Refreshes for this phone's CHO. Does nothing before setup.
  Future<bool> refreshForThisPhone(ApiClient api) async {
    final identity = await ChoStore().load();
    if (identity == null) return false;
    return refresh(api, identity.compoundId);
  }
}
