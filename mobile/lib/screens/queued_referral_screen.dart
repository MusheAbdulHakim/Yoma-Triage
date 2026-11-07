import 'dart:async';

import 'package:flutter/material.dart';

import '../parameters.dart';
import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import '../widgets/manual_contacts_panel.dart';
import 'dispatch_status_screen.dart';
import 'failed_referrals_screen.dart';
import 'stale_referral_screen.dart';

class QueuedReferralScreen extends StatefulWidget {
  final String clientRequestId;
  final OfflineQueue? queue;
  final ApiClient? api;

  /// The facility chosen for this referral.
  final int? facilityId;
  final ContactLauncher launcher;

  const QueuedReferralScreen({
    super.key,
    required this.clientRequestId,
    this.queue,
    this.api,
    this.facilityId,
    this.launcher = launchWithPhone,
  });

  @override
  State<QueuedReferralScreen> createState() => _QueuedReferralScreenState();
}

class _QueuedReferralScreenState extends State<QueuedReferralScreen> {
  late final OfflineQueue _queue;
  late final ApiClient _api;
  bool _retrying = false;
  String? _retryMessage;

  @override
  void initState() {
    super.initState();
    _queue = widget.queue ?? OfflineQueue.shared;
    _api = widget.api ?? ApiClient();
    _queue.changes.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    _queue.changes.removeListener(_onQueueChanged);
    super.dispose();
  }

  /// A send happened without the CHO tapping Retry sync, usually because signal came
  /// back. Show where this referral is now, rather than "not notified" after it was.
  void _onQueueChanged() {
    if (_retrying || _leaving || !mounted) return;
    unawaited(_showWhereItIs(automatic: true));
  }

  bool _leaving = false;

  Future<void> _retrySync() async {
    setState(() {
      _retrying = true;
      _retryMessage = null;
    });

    try {
      await _queue.flush(_api);
      await _showWhereItIs(automatic: false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _retryMessage =
            'Sync could not complete. Referral remains saved on this device.';
      });
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// Moves to the screen for this referral's state: refused, stale, or dispatched. If
  /// it's still waiting, a Retry sync says so; a send by itself stays quiet.
  Future<void> _showWhereItIs({required bool automatic}) async {
    final refused = (await _queue.failed())
        .any((q) => q.clientRequestId == widget.clientRequestId);
    if (!mounted || _leaving) return;
    if (refused) {
      _leaving = true;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FailedReferralsScreen(queue: _queue),
        ),
      );
      return;
    }
    final stale = (await _queue.needsConfirmation())
        .any((q) => q.clientRequestId == widget.clientRequestId);
    if (!mounted || _leaving) return;
    if (stale) {
      _leaving = true;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StaleReferralScreen(
            queue: _queue,
            api: _api,
            launcher: widget.launcher,
          ),
        ),
      );
      return;
    }
    final dispatchId = await _queue.lookupDispatchId(widget.clientRequestId);
    if (!mounted || _leaving) return;
    if (dispatchId == null) {
      if (!automatic) {
        setState(() {
          _retryMessage =
              'Still waiting for coverage. Referral remains saved on this device.';
        });
      }
      return;
    }
    _leaving = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DispatchStatusScreen(
          dispatchId: dispatchId,
          clientRequestId: widget.clientRequestId,
          facilityId: widget.facilityId,
          api: _api,
          queue: _queue,
          launcher: widget.launcher,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Referral Queued')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(
              Icons.check_circle,
              size: 72,
              color: YomaColors.safe,
            ),
            const SizedBox(height: 24),
            const Text(
              'Referral saved on this device. Drivers have not been notified yet. '
              'They will be contacted when this phone has coverage.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              'If it waits more than ${Parameters.staleAfterMinutes} minutes, or you call or '
              'SMS someone below, the app will ask you before alerting drivers.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade800),
            ),
            const SizedBox(height: 16),
            Text(
              'Request: ${widget.clientRequestId}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _queue.retryWarning,
              builder: (context, warning, _) {
                if (warning == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    warning,
                    key: const Key('queued_retry_warning'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: YomaColors.caution,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
            if (_retryMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _retryMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: YomaColors.caution),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _retrying ? null : _retrySync,
              icon: _retrying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(_retrying ? 'Syncing…' : 'Retry sync'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Back to Home'),
            ),
            const SizedBox(height: 24),
            ManualContactsPanel(
              facilityIds: {if (widget.facilityId != null) widget.facilityId!},
              launcher: widget.launcher,
              onContactUsed: () =>
                  _queue.markManualContact(widget.clientRequestId),
            ),
          ],
        ),
      ),
    );
  }
}
