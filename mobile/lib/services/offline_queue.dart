import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/referral.dart';
import 'api_client.dart';

const _serverReferralIdKey = 'local_server_referral_id';
const _manualContactKey = 'local_manual_contact_made';

class QueuedReferral {
  final String clientRequestId;
  final Map<String, dynamic> payload;
  /// pending: will be retried. sent: done. failed: the server refused it, so it
  /// will not be retried and the CHO has to coordinate manually. needs_confirmation:
  /// the server stored it as stale and is waiting for the CHO's answer.
  String status;
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

  // Kept in the payload, under keys that are never sent to the server.
  int? get serverReferralId => payload[_serverReferralIdKey] as int?;
  bool get manualContactMade => payload[_manualContactKey] == true;

  /// How long this has waited, by this phone's clock. A clock set back reads as zero.
  int get ageSeconds {
    final age = DateTime.now().difference(createdAt).inSeconds;
    return age < 0 ? 0 : age;
  }

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

  /// How many referrals the server has refused. The Home screen shows this.
  final ValueNotifier<int> failedCount = ValueNotifier<int>(0);

  /// How many stale referrals are waiting for the CHO's answer.
  final ValueNotifier<int> needsConfirmationCount = ValueNotifier<int>(0);

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

  /// Referrals the server refused, oldest first.
  Future<List<QueuedReferral>> failed() {
    return _serialized(() async {
      final items = await _failedUnlocked();
      failedCount.value = items.length;
      return items;
    });
  }

  /// Stale referrals waiting for the CHO's answer, oldest first.
  Future<List<QueuedReferral>> needsConfirmation() {
    return _serialized(() async {
      final items = await _withStatusUnlocked('needs_confirmation');
      needsConfirmationCount.value = items.length;
      return items;
    });
  }

  /// The CHO has answered, and the server has recorded it.
  Future<void> removeResolved(String clientRequestId) {
    return _serialized(() async {
      for (final queued in await _withStatusUnlocked('needs_confirmation')) {
        if (queued.clientRequestId == clientRequestId) {
          queued.status = 'sent';
          await _persistUnlocked(queued);
        }
      }
      needsConfirmationCount.value =
          (await _withStatusUnlocked('needs_confirmation')).length;
    });
  }

  /// The CHO tapped Call or SMS for this referral. If it turns out to be stale, the
  /// prompt starts on "Already handled".
  Future<void> markManualContact(String clientRequestId) {
    return _serialized(() async {
      for (final status in const ['pending', 'needs_confirmation']) {
        for (final queued in await _withStatusUnlocked(status)) {
          if (queued.clientRequestId == clientRequestId) {
            queued.payload[_manualContactKey] = true;
            await _persistUnlocked(queued);
          }
        }
      }
    });
  }

  /// Records that the server refused this referral, so it is never retried.
  Future<void> markFailed(String clientRequestId, String reason) {
    return _serialized(() async {
      final items = await _pendingUnlocked();
      for (final queued in items) {
        if (queued.clientRequestId == clientRequestId) {
          await _failUnlocked(queued, reason);
        }
      }
      failedCount.value = (await _failedUnlocked()).length;
    });
  }

  Future<void> _failUnlocked(QueuedReferral queued, String reason) async {
    queued.status = 'failed';
    queued.lastError = reason;
    queued.updatedAt = DateTime.now();
    await _persistUnlocked(queued);
  }

  /// Sends pending items. A permanent refusal (see [ApiException.isPermanent]) moves
  /// an item to failed. Network errors, 5xx, 408 and 429 keep it pending for retry.
  Future<int> flush(ApiClient api) {
    return _serialized(() async {
      final items = await _pendingUnlocked();
      var sent = 0;
      for (final queued in items) {
        final chps = _asInt(queued.payload['chps_compound_id']);
        final facility = _asInt(queued.payload['facility_id']);
        final hash = _asString(queued.payload['patient_hash']);
        final choPhone = _asString(queued.payload['cho_phone']);
        final emergency = _asString(queued.payload['emergency_type']);
        final vitalsRaw = queued.payload['vitals'];
        if (chps == null ||
            facility == null ||
            hash == null ||
            choPhone == null ||
            emergency == null ||
            vitalsRaw is! Map) {
          // Retrying can't repair what was saved on this phone.
          await _failUnlocked(queued, 'The saved referral on this phone is invalid');
          continue;
        }
        try {
          final confidence = queued.payload['ai_confidence'];
          final originLat = queued.payload['origin_lat'];
          final originLon = queued.payload['origin_lon'];
          final response = await api.createReferral(
            ReferralRequest(
              clientRequestId: queued.clientRequestId,
              chpsCompoundId: chps,
              facilityId: facility,
              patientHash: hash,
              choPhone: choPhone,
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
              vitalsTaken: queued.payload['vitals_taken'] != false,
              queueAgeSeconds: queued.ageSeconds,
            ),
          );
          final referral = response['referral'];
          if (referral is Map &&
              referral['status'] == 'AWAITING_CONFIRMATION') {
            queued.status = 'needs_confirmation';
            queued.lastError = null;
            queued.updatedAt = DateTime.now();
            queued.payload[_serverReferralIdKey] = _asInt(referral['id']);
            await _persistUnlocked(queued);
            continue;
          }
          final dispatchId = parseDispatchIdFromResponse(response);
          if (dispatchId != null) {
            await _saveDispatchId(queued.clientRequestId, dispatchId);
          }
          queued.status = 'sent';
          queued.lastError = null;
          queued.updatedAt = DateTime.now();
          await _persistUnlocked(queued);
          sent++;
        } on ApiException catch (e) {
          if (e.isPermanent) {
            await _failUnlocked(queued, e.reason);
          } else {
            await _keepPending(queued, e);
          }
        } catch (e) {
          await _keepPending(queued, e);
        }
      }
      failedCount.value = (await _failedUnlocked()).length;
      needsConfirmationCount.value =
          (await _withStatusUnlocked('needs_confirmation')).length;
      return sent;
    });
  }

  Future<void> _keepPending(QueuedReferral queued, Object error) async {
    queued.status = 'pending';
    queued.lastError = error.toString();
    queued.updatedAt = DateTime.now();
    await _persistUnlocked(queued);
  }

  Future<List<QueuedReferral>> _failedUnlocked() => _withStatusUnlocked('failed');

  Future<List<QueuedReferral>> _withStatusUnlocked(String status) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return [
        for (final s in prefs.getStringList(_prefsKey) ?? <String>[])
          if (_decodeRow(s) case final q? when q.status == status) q,
      ];
    }
    final db = await _openDb();
    final rows = await db.query(
      _table,
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Internal pending without re-entering the mutex (caller already holds it).
  Future<List<QueuedReferral>> _pendingUnlocked() => _withStatusUnlocked('pending');

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
