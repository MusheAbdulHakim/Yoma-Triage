import 'package:flutter/material.dart';

import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';

/// Referrals the server refused. They won't be retried, so no driver or hospital
/// has been told and the CHO has to act.
class FailedReferralsScreen extends StatefulWidget {
  const FailedReferralsScreen({super.key, required this.queue});

  final OfflineQueue queue;

  @override
  State<FailedReferralsScreen> createState() => _FailedReferralsScreenState();
}

class _FailedReferralsScreenState extends State<FailedReferralsScreen> {
  late final Future<List<QueuedReferral>> _failed = widget.queue.failed();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Referral NOT sent')),
      body: FutureBuilder<List<QueuedReferral>>(
        future: _failed,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <QueuedReferral>[];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.error, size: 72, color: YomaColors.danger),
              const SizedBox(height: 16),
              const Text(
                'No driver or hospital has been told. '
                'Call the driver and the hospital manually.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              for (final item in items)
                Card(
                  child: ListTile(
                    title: Text(
                      item.payload['emergency_type']?.toString() ?? 'Referral',
                    ),
                    subtitle: Text(
                      'Reason: ${item.lastError ?? 'Unknown'}\n'
                      'Request: ${item.clientRequestId}',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Back to Home'),
              ),
            ],
          );
        },
      ),
    );
  }
}
