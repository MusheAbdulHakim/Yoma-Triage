import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/referral.dart';
import 'api_client.dart';

class QueuedReferral {
  final String clientRequestId;
  final Map<String, dynamic> payload;
  String status; // pending | sent | failed
  String? lastError;
  DateTime createdAt;
  DateTime updatedAt;

  QueuedReferral({
    required this.clientRequestId,
    required this.payload,
    this.status = 'pending',
    this.lastError,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'client_request_id': clientRequestId,
        'payload': payload,
        'status': status,
        'last_error': lastError,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Returns null for corrupt rows instead of throwing.
  static QueuedReferral? tryFromJson(Map<String, dynamic> json) {
    try {
      final id = json['client_request_id'];
      final payload = json['payload'];
      final status = json['status'];
      final created = json['created_at'];
      if (id is! String ||
          payload is! Map ||
          status is! String ||
          created is! String) {
        return null;
      }
      return QueuedReferral(
        clientRequestId: id,
        payload: Map<String, dynamic>.from(payload),
        status: status,
        lastError: json['last_error'] as String?,
        createdAt: DateTime.parse(created),
        updatedAt: DateTime.parse(
          (json['updated_at'] as String?) ?? created,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Offline outbox: SQLite on mobile/desktop; SharedPreferences on web.
///
/// App code should use [OfflineQueue.shared] so writers share one DB handle.
class OfflineQueue {
  static const _prefsKey = 'pending_referrals';
  static const _dispatchIdsKey = 'yoma_dispatch_ids';
  static const _table = 'referral_outbox';

  /// Process-wide queue used by UI + connectivity sync.
  static final OfflineQueue shared = OfflineQueue._();

  Database? _db;
  final DatabaseFactory? databaseFactoryOverride;
  final String? databasePathOverride;
  Future<void> _chain = Future.value();

  OfflineQueue._()
      : databaseFactoryOverride = null,
        databasePathOverride = null;

  /// Isolated instance for unit tests (does not touch [shared]).
  OfflineQueue({
    this.databaseFactoryOverride,
    this.databasePathOverride,
  });

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final factory = databaseFactoryOverride ?? databaseFactory;
    final path = databasePathOverride ??
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          'yoma_triage_outbox.db',
        );
    _db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_table (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              client_request_id TEXT UNIQUE NOT NULL,
              payload_json TEXT NOT NULL,
              status TEXT NOT NULL,
              last_error TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    return _db!;
  }

  Future<void> enqueue(ReferralRequest req) {
    return _serialized(() async {
      final queued = QueuedReferral(
        clientRequestId: req.clientRequestId,
        payload: req.toJson(),
      );
      if (kIsWeb) {
        await _enqueuePrefs(queued);
      } else {
        await _enqueueSqlite(queued);
      }
    });
  }

  QueuedReferral? _decodeRow(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is! Map) return null;
      return QueuedReferral.tryFromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> _enqueuePrefs(QueuedReferral queued) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKey) ?? [];
    final cleaned = <String>[];
    for (final s in list) {
      final q = _decodeRow(s);
      if (q == null) continue; // drop corrupt
      if (q.clientRequestId == queued.clientRequestId) continue;
      cleaned.add(jsonEncode(q.toJson()));
    }
    cleaned.add(jsonEncode(queued.toJson()));
    await prefs.setStringList(_prefsKey, cleaned);
  }

  Future<void> _enqueueSqlite(QueuedReferral queued) async {
    final db = await _openDb();
    final now = DateTime.now().toIso8601String();
    await db.insert(
      _table,
      {
        'client_request_id': queued.clientRequestId,
        'payload_json': jsonEncode(queued.payload),
        'status': queued.status,
        'last_error': queued.lastError,
        'created_at': queued.createdAt.toIso8601String(),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<QueuedReferral>> pending() {
    return _serialized(_pendingUnlocked);
  }

  QueuedReferral _fromRow(Map<String, Object?> row) {
    return QueuedReferral(
      clientRequestId: row['client_request_id']! as String,
      payload: Map<String, dynamic>.from(
        jsonDecode(row['payload_json']! as String) as Map,
      ),
      status: row['status']! as String,
      lastError: row['last_error'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _asString(dynamic v) => v?.toString();

  static int? parseDispatchIdFromResponse(Map<String, dynamic> response) {
    final dispatch = response['dispatch'];
    if (dispatch is! Map) return null;
    final id = dispatch['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }

  Future<void> saveDispatchId(String clientRequestId, int dispatchId) =>
      _saveDispatchId(clientRequestId, dispatchId);

  Future<void> _saveDispatchId(String clientRequestId, int dispatchId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dispatchIdsKey);
    final map = <String, dynamic>{};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          map.addAll(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    map[clientRequestId] = dispatchId;
    await prefs.setString(_dispatchIdsKey, jsonEncode(map));
  }

  /// Lookup dispatch id after a successful flush (for offline → online rebound).
  Future<int?> lookupDispatchId(String clientRequestId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dispatchIdsKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final id = decoded[clientRequestId];
      if (id is int) return id;
      if (id is num) return id.toInt();
    } catch (_) {}
    return null;
  }

  /// Retry pending/failed items. Never silent-drops: failures stay queued.
  Future<int> flush(ApiClient api) {
    return _serialized(() async {
      final items = await _pendingUnlocked();
      var sent = 0;
      for (final queued in items) {
        try {
          final chps = _asInt(queued.payload['chps_compound_id']);
          final facility = _asInt(queued.payload['facility_id']);
          final hash = _asString(queued.payload['patient_hash']);
          final emergency = _asString(queued.payload['emergency_type']);
          final vitalsRaw = queued.payload['vitals'];
          if (chps == null ||
              facility == null ||
              hash == null ||
              emergency == null ||
              vitalsRaw is! Map) {
            throw const FormatException('Invalid queued referral payload');
          }
          final confidence = queued.payload['ai_confidence'];
          final originLat = queued.payload['origin_lat'];
          final originLon = queued.payload['origin_lon'];
          final response = await api.createReferral(
            ReferralRequest(
              clientRequestId: queued.clientRequestId,
              chpsCompoundId: chps,
              facilityId: facility,
              patientHash: hash,
              emergencyType: emergency,
              vitals: Map<String, dynamic>.from(vitalsRaw),
              aiScreenResult: queued.payload['ai_screen_result'] as String?,
              aiConfidence:
                  confidence == null ? null : (confidence as num).toDouble(),
              aiModelVersion: queued.payload['ai_model_version'] as String?,
              catalogVersion: queued.payload['catalog_version'] as String?,
              originLat:
                  originLat == null ? null : (originLat as num).toDouble(),
              originLon:
                  originLon == null ? null : (originLon as num).toDouble(),
              originSource: queued.payload['origin_source'] as String?,
            ),
          );
          final dispatchId = parseDispatchIdFromResponse(response);
          if (dispatchId != null) {
            await _saveDispatchId(queued.clientRequestId, dispatchId);
          }
          queued.status = 'sent';
          queued.lastError = null;
          queued.updatedAt = DateTime.now();
          await _persistUnlocked(queued);
          sent++;
        } catch (e) {
          queued.status = 'pending';
          queued.lastError = e.toString();
          queued.updatedAt = DateTime.now();
          await _persistUnlocked(queued);
        }
      }
      return sent;
    });
  }

  /// Internal pending without re-entering the mutex (caller already holds it).
  Future<List<QueuedReferral>> _pendingUnlocked() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? [];
      final out = <QueuedReferral>[];
      for (final s in list) {
        final q = _decodeRow(s);
        if (q != null && q.status != 'sent') out.add(q);
      }
      return out;
    }
    final db = await _openDb();
    final rows = await db.query(
      _table,
      where: 'status != ?',
      whereArgs: ['sent'],
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> _persistUnlocked(QueuedReferral queued) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? [];
      final updated = <String>[];
      var found = false;
      for (final s in list) {
        final q = _decodeRow(s);
        if (q == null) continue;
        if (q.clientRequestId == queued.clientRequestId) {
          if (queued.status != 'sent') {
            updated.add(jsonEncode(queued.toJson()));
          }
          found = true;
        } else if (q.status != 'sent') {
          updated.add(jsonEncode(q.toJson()));
        }
      }
      if (!found && queued.status != 'sent') {
        updated.add(jsonEncode(queued.toJson()));
      }
      await prefs.setStringList(_prefsKey, updated);
      return;
    }
    final db = await _openDb();
    if (queued.status == 'sent') {
      await db.delete(
        _table,
        where: 'client_request_id = ?',
        whereArgs: [queued.clientRequestId],
      );
      return;
    }
    await db.update(
      _table,
      {
        'status': queued.status,
        'last_error': queued.lastError,
        'updated_at': queued.updatedAt.toIso8601String(),
        'payload_json': jsonEncode(queued.payload),
      },
      where: 'client_request_id = ?',
      whereArgs: [queued.clientRequestId],
    );
  }
}
