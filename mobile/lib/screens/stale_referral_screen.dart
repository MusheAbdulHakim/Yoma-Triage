import 'package:flutter/material.dart';

import '../models/emergency_type.dart';
import '../services/friendly_time.dart';

import '../parameters.dart';

import '../services/api_client.dart';
import '../services/cho_store.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import '../widgets/manual_contacts_panel.dart';
import 'dispatch_status_screen.dart';

/// The server stored these referrals but told nobody, because they waited too long on the
/// phone. A driver could otherwise rush to a patient who left hours ago.
class StaleReferralScreen extends StatefulWidget {
  const StaleReferralScreen({
    super.key,
    required this.queue,
    this.api,
    this.launcher = launchWithPhone,
  });

  final OfflineQueue queue;
  final ApiClient? api;
  final ContactLauncher launcher;

  @override
  State<StaleReferralScreen> createState() => _StaleReferralScreenState();
}

enum _Answer {
  sendNow('send_now', 'Send now', 'Alert drivers now'),
  alreadyHandled('already_handled', 'Already handled', 'Transport was arranged another way'),
  cancel('cancel', 'Cancel', 'This referral is no longer needed');

  const _Answer(this.action, this.label, this.hint);

  final String action;
  final String label;
  final String hint;
}

class _StaleReferralScreenState extends State<StaleReferralScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  List<QueuedReferral> _items = const [];
  final Map<String, _Answer> _chosen = {};
  final Set<String> _sending = {};
  final Map<String, String> _problems = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.queue.needsConfirmation();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loaded = true;
      for (final item in items) {
        if (item.manualContactMade) {
          _chosen.putIfAbsent(item.clientRequestId, () => _Answer.alreadyHandled);
        }
      }
    });
  }

  Future<void> _submit(QueuedReferral item) async {
    final id = item.clientRequestId;
    final answer = _chosen[id];
    final referralId = item.serverReferralId;
    if (answer == null || referralId == null) return;
    setState(() {
      _sending.add(id);
      _problems.remove(id);
    });
    String? problem;
    int? dispatchId;
    try {
      final identity = await ChoStore().load();
      final choPhone = identity?.phone ?? item.payload['cho_phone'] as String;
      final response = await _api.resolveReferral(
        referralId: referralId,
        action: answer.action,
        choPhone: choPhone,
      );
      dispatchId = OfflineQueue.parseDispatchIdFromResponse(response);
      if (dispatchId != null) {
        await widget.queue.saveDispatchId(id, dispatchId);
      }
      await widget.queue.removeResolved(id);
    } on ApiException catch (e) {
      if (e.code == 'REFERRAL_ALREADY_RESOLVED') {
        await widget.queue.removeResolved(id);
      } else if (e.code == 'REFERRAL_EXPIRED') {
        // The server closed it after it waited too long unanswered. Nobody was told, so
        // Already handled and Cancel are done anyway. Send now is not: say so plainly,
        // and make sure it's read, before the referral leaves this phone.
        if (answer == _Answer.sendNow && mounted) await _explainExpired(e.reason);
        await widget.queue.removeResolved(id);
      } else {
        problem =
            e.code == null ? 'Could not save your answer. Try again, or call directly.' : e.reason;
      }
    } catch (_) {
      problem = 'No connection, so your answer was not saved. '
          'Try again, or call directly.';
    }
    if (!mounted) return;
    setState(() {
      _sending.remove(id);
      if (problem != null) _problems[id] = problem;
    });
    if (problem != null) return;
    await _load();
    if (!mounted) return;
    if (dispatchId != null) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DispatchStatusScreen(
            dispatchId: dispatchId,
            clientRequestId: id,
            facilityId: item.payload['facility_id'] as int?,
            api: _api,
            queue: widget.queue,
            launcher: widget.launcher,
          ),
        ),
      );
    } else if (_items.isEmpty) {
      await Navigator.of(context).maybePop();
    }
  }

  Future<void> _explainExpired(String reason) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Drivers were not told'),
          content: Text(
            reason.isNotEmpty
                ? reason
                : 'This referral was closed after '
                    '${Parameters.expireUnconfirmedHours} hours without an answer. If '
                    'transport is still needed, start a new Emergency Referral or phone a '
                    'driver now.',
            key: const Key('stale_expired_message'),
          ),
          actions: [
            TextButton(
              key: const Key('stale_expired_ok'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  Widget _option(QueuedReferral item, _Answer answer) {
    final id = item.clientRequestId;
    final selected = _chosen[id] == answer;
    return ListTile(
      key: Key('stale_${answer.action}_$id'),
      selected: selected,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(answer.label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(answer.hint),
      onTap: () => setState(() => _chosen[id] = answer),
    );
  }

  Widget _card(QueuedReferral item) {
    final id = item.clientRequestId;
    final problem = _problems[id];
    final minutes = item.ageSeconds ~/ 60;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              emergencyTypeLabel(item.payload['emergency_type']?.toString()),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text('Waited ${countOf(minutes < 1 ? 1 : minutes, 'minute')} on this phone. '
                'Drivers have not been told.'),
            if (item.manualContactMade)
              Text(
                'You used Call or SMS for this referral.',
                key: Key('stale_contact_note_$id'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 8),
            for (final answer in _Answer.values) _option(item, answer),
            if (problem != null) ...[
              Text(
                problem,
                key: Key('stale_problem_$id'),
                style: const TextStyle(color: YomaColors.danger),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              key: Key('stale_confirm_$id'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _chosen[id] == null || _sending.contains(id) ? null : () => _submit(item),
              child: Text(_sending.contains(id) ? 'Saving…' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Still needs transport?')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loaded && _items.isEmpty) const Text('Nothing is waiting for your answer.'),
          for (final item in _items) _card(item),
          const SizedBox(height: 16),
          if (_loaded)
            ManualContactsPanel(
              key: ValueKey(_items.length),
              facilityIds: {
                for (final item in _items)
                  if (item.payload['facility_id'] is int) item.payload['facility_id'] as int,
              },
              launcher: widget.launcher,
              onContactUsed: () {
                for (final item in _items) {
                  widget.queue.markManualContact(item.clientRequestId);
                  _chosen.putIfAbsent(
                    item.clientRequestId,
                    () => _Answer.alreadyHandled,
                  );
                }
                setState(() {});
              },
            ),
        ],
      ),
    );
  }
}
