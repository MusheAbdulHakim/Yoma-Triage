import 'dart:async';

import 'package:flutter/material.dart';

import '../parameters.dart';
import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import '../services/dispatch_timeline.dart';
import '../widgets/dispatch_timeline_view.dart';
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
        _retryMessage = 'Sync could not complete. Referral remains saved on this device.';
      });
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// Moves to the screen for this referral's state: refused, stale, or dispatched. If
  /// it's still waiting, a Retry sync says so; a send by itself stays quiet.
  Future<void> _showWhereItIs({required bool automatic}) async {
    final refused = (await _queue.failed()).any((q) => q.clientRequestId == widget.clientRequestId);
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
    final stale =
        (await _queue.needsConfirmation()).any((q) => q.clientRequestId == widget.clientRequestId);
    if (!mounted || _leaving) return;
    if (stale) {
      _leaving = true;
      // Ask over this screen; once answered there is nothing left to wait for here.
      await showStaleReferralSheet(context, queue: _queue, api: _api, launcher: widget.launcher);
      if (mounted) await Navigator.of(context).maybePop();
      return;
    }
    final dispatchId = await _queue.lookupDispatchId(widget.clientRequestId);
    if (!mounted || _leaving) return;
    if (dispatchId == null) {
      if (!automatic) {
        setState(() {
          _retryMessage = 'Still waiting for coverage. Referral remains saved on this device.';
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Referral status')),
      body: SafeArea(
        child: ListView(
          key: const Key('queued_referral'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            DispatchTimelineView(steps: queuedTimeline().steps),
            const SizedBox(height: 16),
            // The offline policy's honesty copy: nobody has been told yet.
            Text(
              'Referral saved on this device. Drivers have not been notified yet. '
              'They will be contacted when this phone has coverage.',
              style: text.bodyLarge?.copyWith(color: YomaColors.grey900),
            ),
            const SizedBox(height: 8),
            Text(
              'If it waits more than ${Parameters.staleAfterMinutes} minutes, or you call or '
              'SMS someone below, the app will ask you before alerting drivers.',
              style: text.bodyMedium?.copyWith(color: YomaColors.grey700),
            ),
            const SizedBox(height: 8),
            Text(
              'Request: ${widget.clientRequestId}',
              style: text.bodySmall?.copyWith(color: YomaColors.grey600),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _queue.retryWarning,
              builder: (context, warning, _) {
                if (warning == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    warning,
                    key: const Key('queued_retry_warning'),
                    style: text.bodyMedium?.copyWith(
                      color: YomaColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
            if (_retryMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _retryMessage!,
                style: text.bodyMedium?.copyWith(color: YomaColors.warning),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _retrying ? null : _retrySync,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: _retrying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(_retrying ? 'Syncing…' : 'Retry sync'),
            ),
            const SizedBox(height: 20),
            const NavyHelpCard(key: Key('queued_help'), text: 'Urgent? Call a driver now'),
            const SizedBox(height: 8),
            ManualContactsPanel(
              facilityIds: {if (widget.facilityId != null) widget.facilityId!},
              launcher: widget.launcher,
              onContactUsed: () => _queue.markManualContact(widget.clientRequestId),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
