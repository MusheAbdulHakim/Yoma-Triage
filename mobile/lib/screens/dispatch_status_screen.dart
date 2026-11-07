import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/cho_store.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import '../widgets/manual_contacts_panel.dart';

/// Shown instead of the network error itself, which means nothing to a CHO.
const dispatchUnreachableMessage =
    'Server unreachable, so this status may be out of date. Your referral was sent, '
    'and this screen will keep checking. Use Call or SMS below if urgent.';

class DispatchStatusScreen extends StatefulWidget {
  final int? dispatchId;
  final String clientRequestId;

  /// The facility chosen for this referral.
  final int? facilityId;
  final ApiClient? api;
  final OfflineQueue? queue;
  final ContactLauncher launcher;

  const DispatchStatusScreen({
    super.key,
    required this.dispatchId,
    required this.clientRequestId,
    this.facilityId,
    this.api,
    this.queue,
    this.launcher = launchWithPhone,
  });

  @override
  State<DispatchStatusScreen> createState() => _DispatchStatusScreenState();
}

class _DispatchStatusScreenState extends State<DispatchStatusScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final OfflineQueue _queue = widget.queue ?? OfflineQueue.shared;
  Timer? _timer;
  int? _dispatchId;
  String _status = 'PENDING';
  String _detail = 'Waiting for dispatch…';
  String? _driverName;
  int? _etaMinutes;
  bool _terminal = false;
  bool _disposed = false;
  int _pollSeconds = 2;
  late int? _facilityId = widget.facilityId;

  /// The last status check couldn't reach the server.
  bool _unreachable = false;

  bool get _needsManualHelp =>
      _status == 'FAILED' || _status == 'QUEUED' || _unreachable;


  bool _cancelling = false;

  static const _terminalStates = {'COMPLETED', 'FAILED', 'DIVERTED', 'CANCELLED'};

  bool get _canCancel =>
      _dispatchId != null && _status != 'COMPLETED' && _status != 'CANCELLED';

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
      final facilityId = data['facility_id'];
      final etaRaw = data['eta_minutes'];
      final eta = etaRaw is int
          ? etaRaw
          : etaRaw is num
              ? etaRaw.toInt()
              : null;
      setState(() {
        _unreachable = false;
        _status = status;
        if (facilityId is int) _facilityId = facilityId;
        _driverName = driverName;
        _etaMinutes = eta;
        final parts = <String>[
          'Dispatch #$id',
          'tier ${data['current_tier'] ?? '-'}',
          if (driverName != null && driverName.isNotEmpty)
            'Driver: $driverName',
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
    } catch (_) {
      if (!mounted || _disposed) return;
      setState(() {
        _unreachable = true;
        _detail = dispatchUnreachableMessage;
        _pollSeconds = (_pollSeconds * 2).clamp(2, 10);
      });
      if (!_terminal && mounted && !_disposed) _schedulePoll();
    }
  }

  Future<void> _confirmCancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this dispatch?'),
        content: const Text(
          'This stops alerting drivers. If a driver has accepted, the driver and the '
          'hospital will be told it is cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            key: const Key('dispatch_cancel_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel dispatch'),
          ),
        ],
      ),
    );
    if (yes == true) await _cancel();
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    String? problem;
    try {
      final identity = await ChoStore().load();
      if (identity == null) {
        problem = 'This phone is not set up. Call the driver and hospital directly.';
      } else {
        final data = await _api.cancelDispatch(
          dispatchId: _dispatchId!,
          choPhone: identity.phone,
        );
        if (!mounted || _disposed) return;
        _timer?.cancel();
        setState(() {
          _status = (data['status'] as String?) ?? 'CANCELLED';
          _terminal = true;
          _driverName = null;
          _etaMinutes = null;
          _detail = 'Drivers will not be alerted any more.';
        });
      }
    } on ApiException catch (e) {
      problem = e.code == null
          ? 'Could not cancel. Call the driver and hospital directly.'
          : e.reason;
    } catch (_) {
      problem =
          'Could not cancel: no connection. Call the driver and hospital directly.';
    }
    if (!mounted || _disposed) return;
    setState(() => _cancelling = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
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
      body: ListView(
        padding: const EdgeInsets.all(24),
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
          const SizedBox(height: 24),
          if (!_terminal && _dispatchId != null)
            const Center(child: CircularProgressIndicator()),
          if (_needsManualHelp) ...[
            const SizedBox(height: 16),
            ManualContactsPanel(
              key: ValueKey(_facilityId),
              facilityIds: {if (_facilityId != null) _facilityId!},
              launcher: widget.launcher,
            ),
          ],
          if (_canCancel) ...[
            const SizedBox(height: 24),
            TextButton(
              key: const Key('dispatch_cancel'),
              style: TextButton.styleFrom(foregroundColor: YomaColors.danger),
              onPressed: _cancelling ? null : _confirmCancel,
              child: Text(_cancelling ? 'Cancelling…' : 'Cancel this dispatch'),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }
}
