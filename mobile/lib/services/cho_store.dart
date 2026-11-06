import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Who this phone belongs to, confirmed by the server at first-run setup.
class ChoIdentity {
  const ChoIdentity({
    required this.phone,
    required this.name,
    required this.compoundId,
    required this.compoundName,
    this.latitude,
    this.longitude,
  });

  final String phone;
  final String name;
  final int compoundId;
  final String compoundName;
  final double? latitude;
  final double? longitude;

  factory ChoIdentity.fromJson(Map<String, dynamic> json) => ChoIdentity(
        phone: json['phone'] as String,
        name: json['name'] as String,
        compoundId: (json['compound_id'] as num).toInt(),
        compoundName: (json['compound_name'] as String?) ?? 'Your CHPS compound',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'name': name,
        'compound_id': compoundId,
        'compound_name': compoundName,
        'latitude': latitude,
        'longitude': longitude,
      };
}

/// There is deliberately no default: until setup succeeds, this phone has no compound.
class ChoStore {
  static const prefsKey = 'cho_identity';

  Future<ChoIdentity?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return null;
    try {
      return ChoIdentity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(ChoIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(identity.toJson()));
  }
}
