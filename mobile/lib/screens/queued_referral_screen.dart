import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import 'dispatch_status_screen.dart';

class QueuedReferralScreen extends StatefulWidget {
  final String clientRequestId;
  final OfflineQueue? queue;
  final ApiClient? api;

  const QueuedReferralScreen({
    super.key,
    required this.clientRequestId,
    this.queue,
    this.api,
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
  }

  Future<void> _retrySync() async {
    setState(() {
      _retrying = true;
      _retryMessage = null;
    });

    try {
      await _queue.flush(_api);
      final dispatchId = await _queue.lookupDispatchId(widget.clientRequestId);
      if (!mounted) return;
      if (dispatchId == null) {
        setState(() {
          _retryMessage =
              'Still waiting for coverage. Referral remains saved on this device.';
        });
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DispatchStatusScreen(
            dispatchId: dispatchId,
            clientRequestId: widget.clientRequestId,
          ),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Referral Queued')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
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
              const SizedBox(height: 16),
              Text(
                'Request: ${widget.clientRequestId}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              if (_retryMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _retryMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: YomaColors.caution),
                ),
              ],
              const Spacer(),
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
            ],
          ),
        ),
      ),
    );
  }
}
