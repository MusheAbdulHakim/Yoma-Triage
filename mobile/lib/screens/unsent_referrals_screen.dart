import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import '../widgets/manual_contacts_panel.dart';
import 'failed_referrals_screen.dart';
import 'stale_referral_screen.dart';

/// Everything on this phone that hasn't reached a driver, with the means to act on it.
/// Reachable from setup, when this CHO may no longer be able to send.
class UnsentReferralsScreen extends StatefulWidget {
  const UnsentReferralsScreen({
    super.key,
    required this.queue,
    this.api,
    this.launcher = launchWithPhone,
  });

  final OfflineQueue queue;
  final ApiClient? api;
  final ContactLauncher launcher;

  @override
  State<UnsentReferralsScreen> createState() => _UnsentReferralsScreenState();
}

class _UnsentReferralsScreenState extends State<UnsentReferralsScreen> {
  late Future<List<QueuedReferral>> _items = widget.queue.unsent();

  String _statusText(QueuedReferral item) => switch (item.status) {
        'failed' => 'NOT sent: ${item.lastError ?? 'refused by the server'}',
        'needs_confirmation' => 'Waiting for your answer. Tap to answer.',
        _ => 'Saved on this phone. Drivers have not been told.',
      };

  Future<void> _open(QueuedReferral item) async {
    final Widget? screen = switch (item.status) {
      'failed' => FailedReferralsScreen(queue: widget.queue, launcher: widget.launcher),
      'needs_confirmation' => StaleReferralScreen(
          queue: widget.queue,
          api: widget.api,
          launcher: widget.launcher,
        ),
      _ => null,
    };
    if (screen == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    setState(() {
      _items = widget.queue.unsent();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unsent referrals')),
      body: FutureBuilder<List<QueuedReferral>>(
        future: _items,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <QueuedReferral>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'No driver has been told about these. Call or SMS below.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final item in items)
                Card(
                  child: ListTile(
                    key: Key('unsent_${item.clientRequestId}'),
                    leading: const Icon(Icons.error, color: YomaColors.danger),
                    title: Text(
                      item.payload['emergency_type']?.toString() ?? 'Referral',
                    ),
                    subtitle: Text(_statusText(item)),
                    onTap: () => _open(item),
                  ),
                ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.done)
                ManualContactsPanel(
                  facilityIds: {
                    for (final item in items)
                      if (item.payload['facility_id'] is int)
                        item.payload['facility_id'] as int,
                  },
                  launcher: widget.launcher,
                  onContactUsed: () {
                    for (final item in items) {
                      widget.queue.markManualContact(item.clientRequestId);
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
