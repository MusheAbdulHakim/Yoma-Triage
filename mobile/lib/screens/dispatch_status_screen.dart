import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';

class DispatchStatusScreen extends StatefulWidget {
  final int? dispatchId;
  final String clientRequestId;

  const DispatchStatusScreen({
    super.key,
    required this.dispatchId,
    required this.clientRequestId,
  });

  @override
  State<DispatchStatusScreen> createState() => _DispatchStatusScreenState();
}

class _DispatchStatusScreenState extends State<DispatchStatusScreen> {
  final _api = ApiClient();
  final _queue = OfflineQueue.shared;
  Timer? _timer;
  int? _dispatchId;
  String _status = 'PENDING';
  String _detail = 'Waiting for dispatch…';
  String? _driverName;
  int? _etaMinutes;
  bool _terminal = false;
  bool _disposed = false;
  int _pollSeconds = 2;

  static const _terminalStates = {'COMPLETED', 'FAILED', 'DIVERTED'};

  @override
  void initState() {
    super.initState();
    _dispatchId = widget.dispatchId;
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_dispatchId == null) {
      final stored = await _queue.lookupDispatchId(widget.clientRequestId);
      if (stored != null && mounted && !_disposed) {
        setState(() {
          _dispatchId = stored;
          _status = 'PENDING';
          _detail = 'Dispatch synced — tracking live status…';
        });
      }
    }
    if (_dispatchId != null) {
      _schedulePoll(immediate: true);
    } else {
      if (mounted && !_disposed) {
        setState(() {
          _status = 'QUEUED';
          _detail =
              'Referral saved offline (${widget.clientRequestId}). Will retry when online.';
        });
      }
      _timer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_disposed) unawaited(_retryFlush());
      });
    }
  }

  void _schedulePoll({bool immediate = false}) {
    _timer?.cancel();
    if (_disposed || _terminal) return;
    if (immediate) {
      unawaited(_poll());
    }
    _timer = Timer(Duration(seconds: _pollSeconds), () {
      if (!_disposed) unawaited(_poll());
    });
  }

  Future<void> _retryFlush() async {
    try {
      await _queue.flush(_api);
      final dispatchId =
          _dispatchId ?? await _queue.lookupDispatchId(widget.clientRequestId);
      if (dispatchId != null && mounted && !_disposed) {
        final wasQueued = _dispatchId == null;
        setState(() {
          _dispatchId = dispatchId;
          if (wasQueued) {
            _status = 'PENDING';
            _detail = 'Dispatch synced — tracking live status…';
          }
        });
        if (wasQueued) {
          _timer?.cancel();
          _schedulePoll(immediate: true);
        }
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    final id = _dispatchId;
    if (id == null || _terminal || _disposed) return;
    try {
      final data = await _api.getDispatch(id);
      if (!mounted || _disposed) return;
      final status = (data['status'] as String?) ?? 'UNKNOWN';
      final driverName = data['driver_name'] as String?;
      final etaRaw = data['eta_minutes'];
      final eta = etaRaw is int
          ? etaRaw
          : etaRaw is num
              ? etaRaw.toInt()
              : null;
      setState(() {
        _status = status;
        _driverName = driverName;
        _etaMinutes = eta;
        final parts = <String>[
          'Dispatch #$id',
          'tier ${data['current_tier'] ?? '-'}',
          if (driverName != null && driverName.isNotEmpty) 'Driver: $driverName',
          if (eta != null) 'ETA: ${eta}m',
        ];
        _detail = parts.join(' · ');
        _pollSeconds = 2;
        if (_terminalStates.contains(status.toUpperCase())) {
          _terminal = true;
          _timer?.cancel();
        }
      });
      if (!_terminal && mounted && !_disposed) _schedulePoll();
    } catch (e) {
      if (!mounted || _disposed) return;
      setState(() {
        _detail = 'Polling… ($e)';
        _pollSeconds = (_pollSeconds * 2).clamp(2, 10);
      });
      if (!_terminal && mounted && !_disposed) _schedulePoll();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dispatch Status'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: YomaColors.brand,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade800),
            ),
            if (_driverName != null || _etaMinutes != null) ...[
              const SizedBox(height: 12),
              Text(
                [
                  if (_driverName != null) 'Driver: $_driverName',
                  if (_etaMinutes != null) 'ETA: ${_etaMinutes}m',
                ].join('  ·  '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: YomaColors.brand,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Request: ${widget.clientRequestId}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Spacer(),
            if (!_terminal && _dispatchId != null)
              const Center(child: CircularProgressIndicator()),
            const Spacer(),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
