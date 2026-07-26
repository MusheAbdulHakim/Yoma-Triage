import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'api_client.dart';
import 'offline_queue.dart';

/// Flushes the offline outbox whenever connectivity returns.
class QueueSyncService {
  QueueSyncService({
    OfflineQueue? queue,
    ApiClient? api,
    Connectivity? connectivity,
  })  : _queue = queue ?? OfflineQueue.shared,
        _api = api ?? ApiClient(),
        _connectivity = connectivity ?? Connectivity();

  final OfflineQueue _queue;
  final ApiClient _api;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _flushing = false;

  void start() {
    _sub?.cancel();
    try {
      _sub = _connectivity.onConnectivityChanged.listen(_onChange);
    } catch (_) {
      // Tests / unsupported platforms: skip live listener.
    }
    // Also try once at startup in case items were left pending.
    unawaited(flushNow());
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onChange(List<ConnectivityResult> results) async {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online) await flushNow();
  }

  Future<int> flushNow() async {
    if (_flushing) return 0;
    _flushing = true;
    try {
      return await _queue.flush(_api);
    } catch (_) {
      return 0;
    } finally {
      _flushing = false;
    }
  }
}
