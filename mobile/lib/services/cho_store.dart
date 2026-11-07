import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

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
  static const noticePrefsKey = 'cho_setup_notice';

  /// Bumped whenever this phone's identity is taken away, so the app can return to setup.
  static final removals = ValueNotifier<int>(0);

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
    await prefs.remove(noticePrefsKey);
  }

  /// Why this phone was returned to setup, if it was.
  Future<String?> loadNotice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(noticePrefsKey);
  }

  Future<void> _remove(String notice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    await prefs.setString(noticePrefsKey, notice);
    removals.value++;
  }

  /// Asks the server whether this CHO is still active at this compound. Returns true if
  /// not, in which case this phone goes back to setup.
  ///
  /// Only a defined refusal or a clear answer counts. A network error, or a page from a
  /// captive portal, says nothing about this CHO and must never log them out.
  Future<bool> recheck(ApiClient api) async {
    final identity = await load();
    if (identity == null) return false;
    final ChoIdentity current;
    try {
      current = ChoIdentity.fromJson(await api.lookupCho(identity.phone));
    } on ApiException catch (e) {
      if (e.code == 'CHO_NOT_ACTIVE') {
        await _remove(
          'This phone number is no longer active as a CHO. '
          'Ask your district coordinator if this is wrong.',
        );
        return true;
      }
      if (e.code == 'CHO_NOT_REGISTERED') {
        await _remove(
          'This phone number is no longer registered as a CHO. '
          'Ask your district coordinator if this is wrong.',
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
    if (current.compoundId != identity.compoundId) {
      await _remove(
        'You have been moved to ${current.compoundName}. '
        'Confirm your number to set up this phone for your new compound.',
      );
      return true;
    }
    await save(current);
    return false;
  }
}
