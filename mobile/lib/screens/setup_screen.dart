import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/yoma_theme.dart';
import '../services/api_client.dart';
import '../services/cho_store.dart';
import '../services/contacts_store.dart';
import '../services/offline_queue.dart';
import '../widgets/manual_contacts_panel.dart';
import 'unsent_referrals_screen.dart';

/// First run: the server confirms this CHO and says which compound they belong to.
/// There is no compound picker, so a phone can't be set up against the wrong one.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.onComplete,
    this.api,
    this.store,
    this.queue,
    this.launcher = launchWithPhone,
  });

  final ValueChanged<ChoIdentity> onComplete;
  final ApiClient? api;
  final ChoStore? store;
  final OfflineQueue? queue;
  final ContactLauncher launcher;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _phone = TextEditingController();
  late final ApiClient _api = widget.api ?? ApiClient();
  late final ChoStore _store = widget.store ?? ChoStore();
  late final OfflineQueue _queue = widget.queue ?? OfflineQueue.shared;
  String? _notice;
  int _unsentCount = 0;
  int _expiringCount = 0;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReturnState();
  }

  /// A phone sent back here may still hold referrals the CHO must not lose sight of.
  Future<void> _loadReturnState() async {
    final notice = await _store.loadNotice();
    var unsent = 0;
    var expiring = 0;
    try {
      unsent = (await _queue.unsent()).length;
      expiring = await _queue.noteExpiryWarning();
    } catch (_) {
      // Setup must still work if the local queue can't be read.
    }
    if (!mounted) return;
    setState(() {
      _notice = notice;
      _unsentCount = unsent;
      _expiringCount = expiring;
    });
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter your phone number');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? error;
    ChoIdentity? identity;
    try {
      identity = ChoIdentity.fromJson(await _api.lookupCho(phone));
      await _store.save(identity);
      // Saved as soon as setup works, in case the network is gone by the next emergency.
      unawaited(ContactsStore().refresh(_api, identity.compoundId));
    } on ApiException catch (e) {
      error = e.statusCode >= 500
          ? 'The server is having a problem. Try again shortly.'
          : e.code == null
              ? 'Could not reach the Yoma server. If you are on Wi-Fi, you may need '
                  'to log in to it. Try again.'
              : e.reason;
    } catch (_) {
      error = 'No connection. Setup needs internet once. '
          'If this is an emergency, call the driver and hospital directly.';
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
    if (identity != null) widget.onComplete(identity);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up this phone')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_notice != null) ...[
            Card(
              color: YomaColors.caution.withValues(alpha: 0.15),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _notice!,
                  key: const Key('setup_notice'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_unsentCount > 0) ...[
            Card(
              color: YomaColors.danger.withValues(alpha: 0.15),
              child: ListTile(
                key: const Key('setup_unsent'),
                leading: const Icon(Icons.error, color: YomaColors.danger),
                title: Text(
                  _unsentCount == 1
                      ? '1 referral has not reached a driver'
                      : '$_unsentCount referrals have not reached a driver',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _expiringCount > 0
                      ? 'Tap to see them, and to Call or SMS. '
                          '$_expiringCount will soon be deleted from this phone.'
                      : 'Tap to see them, and to Call or SMS.',
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UnsentReferralsScreen(
                        queue: _queue,
                        api: _api,
                        launcher: widget.launcher,
                      ),
                    ),
                  );
                  await _loadReturnState();
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Enter the phone number you were registered with as a CHO.',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('setup_phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Your phone number'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('setup_error'),
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Checking…' : 'Continue'),
          ),
        ],
      ),
    );
  }
}
