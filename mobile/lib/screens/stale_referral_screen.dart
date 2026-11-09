import 'package:flutter/material.dart';

import '../models/emergency_type.dart';
import '../parameters.dart';
import '../services/api_client.dart';
import '../services/catalog_store.dart';
import '../services/cho_store.dart';
import '../services/friendly_time.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import '../widgets/manual_contacts_panel.dart';
import 'dispatch_status_screen.dart';

/// The server stored these referrals but told nobody, because they waited too long on the
/// phone. A driver could otherwise rush to a patient who left hours ago.
///
/// Round 7: a bottom sheet over the current screen (the Stitch design), one referral at a
/// time ("1 of 3"), three one-tap answers, and no way to dismiss it without one. The answers
/// and what they do are unchanged from the old page.
Future<void> showStaleReferralSheet(
  BuildContext context, {
  required OfflineQueue queue,
  ApiClient? api,
  ContactLauncher launcher = launchWithPhone,
}) async {
  final client = api ?? ApiClient();
  final outcome = await showModalBottomSheet<_SentToDrivers>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: YomaColors.surface,
    barrierColor: YomaColors.neutral.withValues(alpha: 0.6),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => StaleReferralSheet(queue: queue, api: client, launcher: launcher),
  );
  if (outcome == null || !context.mounted) return;
  // Send now went out: follow it on the status screen, as before.
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DispatchStatusScreen(
        dispatchId: outcome.dispatchId,
        clientRequestId: outcome.clientRequestId,
        facilityId: outcome.facilityId,
        api: client,
        queue: queue,
        launcher: launcher,
      ),
    ),
  );
}

/// Which referral went to drivers, for the status screen after the sheet closes.
class _SentToDrivers {
  const _SentToDrivers(this.dispatchId, this.clientRequestId, this.facilityId);

  final int dispatchId;
  final String clientRequestId;
  final int? facilityId;
}

enum _Answer {
  sendNow('send_now', 'Send now'),
  alreadyHandled('already_handled', 'Already handled'),
  cancel('cancel', 'Cancel referral');

  const _Answer(this.action, this.label);

  /// The API's action name: send_now, already_handled or cancel.
  final String action;
  final String label;
}

/// The sheet's content. Public for tests; open it with [showStaleReferralSheet].
class StaleReferralSheet extends StatefulWidget {
  const StaleReferralSheet({
    super.key,
    required this.queue,
    required this.api,
    this.launcher = launchWithPhone,
  });

  final OfflineQueue queue;
  final ApiClient api;
  final ContactLauncher launcher;

  @override
  State<StaleReferralSheet> createState() => _StaleReferralSheetState();
}

class _StaleReferralSheetState extends State<StaleReferralSheet> {
  List<QueuedReferral> _items = const [];
  Map<int, String> _facilityNames = const {};
  bool _loaded = false;

  /// Answered in this sheet so far, for "2 of 3".
  int _answered = 0;
  _Answer? _sending;
  String? _problem;

  QueuedReferral? get _current => _items.isEmpty ? null : _items.first;

  @override
  void initState() {
    super.initState();
    _loadNames();
    _load();
  }

  Future<void> _loadNames() async {
    try {
      final graph = await CatalogStore().load();
      if (!mounted) return;
      setState(() => _facilityNames = {for (final f in graph.facilities) f.id: f.name});
    } catch (_) {
      // Without the catalog the sheet still shows the emergency type and age.
    }
  }

  Future<void> _load() async {
    final items = await widget.queue.needsConfirmation();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loaded = true;
    });
    if (items.isEmpty) Navigator.of(context).pop();
  }

  Future<void> _answer(QueuedReferral item, _Answer answer) async {
    final id = item.clientRequestId;
    final referralId = item.serverReferralId;
    if (referralId == null || _sending != null) return;
    setState(() {
      _sending = answer;
      _problem = null;
    });
    String? problem;
    int? dispatchId;
    try {
      final identity = await ChoStore().load();
      final choPhone = identity?.phone ?? item.payload['cho_phone'] as String;
      final response = await widget.api.resolveReferral(
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
      problem = 'No connection, so your answer was not saved. Try again, or call directly.';
    }
    if (!mounted) return;
    setState(() {
      _sending = null;
      _problem = problem;
      if (problem == null) _answered++;
    });
    if (problem != null) return;
    if (dispatchId != null) {
      Navigator.of(context)
          .pop(_SentToDrivers(dispatchId, id, item.payload['facility_id'] as int?));
      return;
    }
    await _load(); // the next one, or close when none is left
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

  /// The old page's "Reach them yourself" list. Using Call or SMS there marks this
  /// referral, which makes "Already handled" the main answer.
  Future<void> _openContacts(QueuedReferral item) async {
    final facility = item.payload['facility_id'];
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Call or SMS a driver')),
          body: ListView(
            padding: const EdgeInsets.all(YomaSpacing.lg),
            children: [
              ManualContactsPanel(
                key: const Key('stale_contacts'),
                facilityIds: {if (facility is int) facility},
                launcher: widget.launcher,
                onContactUsed: () => widget.queue.markManualContact(item.clientRequestId),
              ),
            ],
          ),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final item = _current;
    return PopScope(
      // The CHO must choose: Android back does not close it either.
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: !_loaded || item == null
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : _content(context, item),
      ),
    );
  }

  Widget _content(BuildContext context, QueuedReferral item) {
    final text = Theme.of(context).textTheme;
    final id = item.clientRequestId;
    final type = emergencyTypeLabel(item.payload['emergency_type']?.toString());
    final facility = _facilityNames[item.payload['facility_id']];
    final total = _answered + _items.length;
    // Call or SMS already used: Already handled leads (it replaces the old preselected radio).
    final contacted = item.manualContactMade;
    final primary = contacted ? _Answer.alreadyHandled : _Answer.sendNow;
    final secondary = contacted ? _Answer.sendNow : _Answer.alreadyHandled;

    Widget label(_Answer answer) => Text(_sending == answer ? 'Saving…' : answer.label);
    VoidCallback? tap(_Answer answer) => _sending != null ? null : () => _answer(item, answer);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The design's handle. The sheet can't be dragged away; it only shows the shape.
          ExcludeSemantics(
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: YomaColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Still needs transport?',
                    style: text.headlineSmall?.copyWith(color: YomaColors.grey900),
                  ),
                ),
              ),
              if (total > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Text(
                    '${_answered + 1} of $total',
                    key: const Key('stale_position'),
                    style: text.labelMedium?.copyWith(color: YomaColors.grey700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            facility == null ? type : '$type → $facility',
            key: Key('stale_what_$id'),
            style: text.titleMedium?.copyWith(color: YomaColors.grey900),
          ),
          const SizedBox(height: 2),
          Text(
            'Saved ${ago(Duration(seconds: item.ageSeconds))}',
            key: Key('stale_age_$id'),
            style: text.bodyMedium?.copyWith(color: YomaColors.grey700),
          ),
          if (contacted) ...[
            const SizedBox(height: 8),
            Text(
              'You called or texted a driver for this referral.',
              key: Key('stale_contact_note_$id'),
              style: text.bodyMedium?.copyWith(
                color: YomaColors.grey900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: Key('stale_${primary.action}_$id'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: tap(primary),
            child: label(primary),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: Key('stale_${secondary.action}_$id'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: tap(secondary),
            child: label(secondary),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: Key('stale_cancel_$id'),
            style: TextButton.styleFrom(foregroundColor: YomaColors.grey700),
            onPressed: tap(_Answer.cancel),
            child: label(_Answer.cancel),
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _problem!,
                key: Key('stale_problem_$id'),
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: YomaColors.error),
              ),
            ),
          Center(
            child: TextButton(
              key: Key('stale_call_or_sms_$id'),
              onPressed: _sending != null ? null : () => _openContacts(item),
              child: const Text('Call or SMS a driver'),
            ),
          ),
        ],
      ),
    );
  }
}
