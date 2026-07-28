import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/facility_catalog.dart';
import 'api_client.dart';

/// Loads/syncs the Northern Region referral-graph catalog.
class CatalogStore {
  static const bootstrapAsset = 'assets/catalog/northern_bootstrap.json';
  static const syncedFileName = 'referral_graph_northern.json';
  static const homeChpsPrefsKey = FacilityConfig.homeChpsPrefsKey;

  final ApiClient? api;

  CatalogStore({this.api});

  Future<int> homeChpsCompoundId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(homeChpsPrefsKey) ?? 1;
  }

  Future<void> setHomeChpsCompoundId(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(homeChpsPrefsKey, id);
  }

  Future<DateTime?> lastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(CatalogConfig.syncedAtPrefsKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<String?> cachedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(CatalogConfig.catalogVersionPrefsKey);
  }

  Future<bool> isStale({DateTime? now}) async {
    final synced = await lastSyncedAt();
    if (synced == null) {
      // Bootstrap-only until first successful sync — treat as stale to encourage sync.
      return true;
    }
    final age = (now ?? DateTime.now()).difference(synced);
    return age.inDays > CatalogConfig.staleAfterDays;
  }

  Future<ReferralGraph> load() async {
    if (!kIsWeb) {
      try {
        final file = await _syncedFile();
        if (await file.exists()) {
          final text = await file.readAsString();
          return ReferralGraph.fromJson(
            jsonDecode(text) as Map<String, dynamic>,
          );
        }
      } catch (_) {
        // Fall through to bootstrap asset.
      }
    }
    final asset = await rootBundle.loadString(bootstrapAsset);
    return ReferralGraph.fromJson(jsonDecode(asset) as Map<String, dynamic>);
  }

  Future<void> sync(ApiClient client) async {
    final body = await client.getReferralGraph(region: 'northern');
    final prefs = await SharedPreferences.getInstance();
    final version = body['version']?.toString() ?? '';
    await prefs.setString(
      CatalogConfig.syncedAtPrefsKey,
      DateTime.now().toUtc().toIso8601String(),
    );
    if (version.isNotEmpty) {
      await prefs.setString(CatalogConfig.catalogVersionPrefsKey, version);
    }
    if (kIsWeb) {
      // Web: prefs timestamp only; keep bootstrap asset as graph source.
      return;
    }
    final file = await _syncedFile();
    await file.writeAsString(jsonEncode(body));
  }

  /// Best-effort sync used at app start; never throws to UI callers.
  Future<bool> trySyncOnConnect(ApiClient client) async {
    try {
      await sync(client);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File> _syncedFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, syncedFileName));
  }
}
