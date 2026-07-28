import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/facility_catalog.dart';
import 'api_client.dart';

/// Loads/syncs the Northern Region referral-graph catalog.
class CatalogStore {
  static const bootstrapAsset = 'assets/catalog/northern_bootstrap.json';
  static const syncedFileName = 'referral_graph_northern.json';
  static const homeChpsPrefsKey = 'home_chps_compound_id';

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
    if (kIsWeb) {
      // Web: keep bootstrap only for now (no durable app-docs write path).
      return;
    }
    final file = await _syncedFile();
    await file.writeAsString(jsonEncode(body));
  }

  Future<File> _syncedFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, syncedFileName));
  }
}
