import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../services/api_client.dart';
import '../services/cho_store.dart';
import '../services/offline_queue.dart';
import '../theme/yoma_theme.dart';
import '../services/dispatch_timeline.dart';
import '../services/friendly_time.dart';
import '../widgets/dispatch_timeline_view.dart';
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

class _DispatchStatusScreenState extends State<DispatchStatusScreen> with WidgetsBindingObserver {
  late final ApiClient _api = widget.api ?? ApiClient();
  late final OfflineQueue _queue = widget.queue ?? OfflineQueue.shared;
  Timer? _timer;
  int? _dispatchId;
  String _status = 'PENDING';
  String? _driverName;

  /// The driver-facing Ref (the referral id), as on the drivers' offers. Never the
  /// hospital's reply code, which the API does not send to the CHO anyway.
  int? _referralId;

  /// When each step happened, from the API's step_times.
  Map<String, DateTime?> _times = const {};

  /// Seen by this screen, for the timeline's wording only.
  bool _sawFailed = false;
  bool _sawConfirmed = false;

  /// The CHO tapped "Call a driver instead" while drivers were being alerted.
  bool _showContacts = false;
  String? _announcedStep;

  /// Where the patient is going now, and where a hospital diverted them from.
  String? _facilityName;
  String? _divertedFrom;
  bool _terminal = false;
  bool _disposed = false;
  int _pollSeconds = 2;
  late int? _facilityId = widget.facilityId;

  /// The last status check couldn't reach the server.
  bool _unreachable = false;

  /// Until then a driver can still accept a FAILED dispatch (from the API).
  DateTime? _lateClaimUntil;

  /// How often to look again after FAILED, while a late acceptance is still possible.
  static const lateClaimPoll = Duration(seconds: 30);

  /// FAILED, but a driver can still claim it: keep checking, more slowly.
  bool get _watchingForLateClaim =>
      _status.toUpperCase() == 'FAILED' &&
      _lateClaimUntil != null &&
      DateTime.now().isBefore(_lateClaimUntil!);

  bool get _needsManualHelp => _status == 'FAILED' || _status == 'QUEUED' || _unreachable;

  bool _cancelling = false;

  /// A diversion only changes the destination, so the screen keeps following the trip.
  static const _terminalStates = {'COMPLETED', 'FAILED', 'CANCELLED'};

  bool get _canCancel => _dispatchId != null && _status != 'COMPLETED' && _status != 'CANCELLED';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dispatchId = widget.dispatchId;
    unawaited(_bootstrap());
  }

  /// The CHO phoned a driver from this screen before any driver had accepted; ask on
  /// return whether one agreed.
  bool _askIfDriverAgreed = false;

  /// No confirm before calling: the call starts at once, and the question waits for the
  /// CHO to come back to the app.
  Future<bool> _launchContact(Uri uri) async {
    final opened = await widget.launcher(uri);
    if (opened && uri.scheme == 'tel' && _canCancel && _driverName == null) {
      _askIfDriverAgreed = true;
    }
    return opened;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_askIfDriverAgreed) return;
    _askIfDriverAgreed = false;
    if (!mounted || _disposed || !_canCancel || _driverName != null) return;
    unawaited(_askDriverAgreed());
  }

  /// Yes: the referral is cancelled through the normal cancel, so drivers stop being
  /// alerted. No: nothing changes and the screen keeps waiting.
  Future<void> _askDriverAgreed() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('dispatch_driver_agreed'),
        title: const Text('Did a driver agree to come?'),
        content: const Text(
          'If yes, this referral is cancelled so other drivers stop being alerted.',
        ),
        actions: [
          TextButton(
            key: const Key('dispatch_driver_agreed_no'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No, keep waiting'),
          ),
          TextButton(
            key: const Key('dispatch_driver_agreed_yes'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, cancel referral'),
          ),
        ],
      ),
    );
    if (agreed == true && mounted && !_disposed && _canCancel) await _cancel();
  }

  Future<void> _bootstrap() async {
    if (_dispatchId == null) {
      final stored = await _queue.lookupDispatchId(widget.clientRequestId);
      if (stored != null && mounted && !_disposed) {
        setState(() {
          _dispatchId = stored;
          _status = 'PENDING';
        });
      }
    }
    if (_dispatchId != null) {
      _schedulePoll(immediate: true);
    } else {
      if (mounted && !_disposed) {
        setState(() {
          _status = 'QUEUED';
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
      final dispatchId = _dispatchId ?? await _queue.lookupDispatchId(widget.clientRequestId);
      if (dispatchId != null && mounted && !_disposed) {
        final wasQueued = _dispatchId == null;
        setState(() {
          _dispatchId = dispatchId;
          if (wasQueued) _status = 'PENDING';
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
      final facilityName = data['facility_name'] as String?;
      final divertedFrom = data['diverted_from'] as String?;
      final referralId = data['referral_id'];
      final rawTimes = data['step_times'];
      final lateUntil = data['late_claim_until'];
      setState(() {
        _unreachable = false;
        _status = status;
        if (status.toUpperCase() == 'FAILED') _sawFailed = true;
        if (status.toUpperCase() == 'HOSPITAL_CONFIRMED') _sawConfirmed = true;
        if (referralId is int) _referralId = referralId;
        if (rawTimes is Map) {
          _times = {
            for (final MapEntry(:key, :value) in rawTimes.entries)
              '$key': value is String ? DateTime.tryParse(value) : null,
          };
        }
        if (facilityId is int) _facilityId = facilityId;
        _facilityName = facilityName;
        _divertedFrom = divertedFrom;
        _driverName = driverName;
        if (lateUntil is String) _lateClaimUntil = DateTime.tryParse(lateUntil);
        _pollSeconds = _watchingForLateClaim ? lateClaimPoll.inSeconds : 2;
        // FAILED stays open until the late-claim window ends, so a late acceptance shows.
        if (_terminalStates.contains(status.toUpperCase()) && !_watchingForLateClaim) {
          _terminal = true;
          _timer?.cancel();
        }
      });
      if (!_terminal && mounted && !_disposed) _schedulePoll();
    } catch (_) {
      if (!mounted || _disposed) return;
      setState(() {
        _unreachable = true;
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
        });
      }
    } on ApiException catch (e) {
      problem =
          e.code == null ? 'Could not cancel. Call the driver and hospital directly.' : e.reason;
    } catch (_) {
      problem = 'Could not cancel: no connection. Call the driver and hospital directly.';
    }
    if (!mounted || _disposed) return;
    setState(() => _cancelling = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  DispatchTimeline get _timeline => _status == 'QUEUED'
      ? queuedTimeline()
      : dispatchTimeline(
          status: _status,
          driverName: _driverName,
          facilityName: _facilityName,
          divertedFrom: _divertedFrom,
          sawConfirmed: _sawConfirmed,
          acceptedLate: _sawFailed,
          times: _times,
        );

  /// Says the current step aloud when it changes (after the first build).
  void _announceStep(TimelineStep? step) {
    final label = step?.label;
    if (label == null || label == _announcedStep) return;
    final first = _announcedStep == null;
    _announcedStep = label;
    if (first) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.sendAnnouncement(View.of(context), label, TextDirection.ltr);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final timeline = _timeline;
    _announceStep(timeline.current);
    final help = switch (timeline.help) {
      DispatchHelp.noDriver => 'No driver has accepted. Call one now.',
      DispatchHelp.notSentYet => 'Urgent? Call a driver now',
      DispatchHelp.none => null,
    };
    final showContacts = _needsManualHelp || _showContacts;

    return Scaffold(
      appBar: AppBar(
        // Where the patient is going, one line under the title; it changes after a diversion.
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Referral status'),
            if (_facilityName != null)
              Text(
                'Going to: $_facilityName',
                key: const Key('dispatch_destination'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: YomaColors.grey700),
              ),
          ],
        ),
        actions: [
          if (_referralId != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'Ref $_referralId',
                  key: const Key('dispatch_ref'),
                  style: text.labelMedium?.copyWith(color: YomaColors.grey700),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        key: const Key('dispatch_scroll'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          if (_unreachable) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: YomaColors.grey100,
                borderRadius: BorderRadius.circular(YomaRadii.md),
                border: Border.all(color: YomaColors.grey200),
              ),
              child: Text(
                dispatchUnreachableMessage,
                style: text.bodyMedium?.copyWith(color: YomaColors.grey800),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // When the CHO has to act (no driver, not sent, no connection), the design puts the
          // banner and the Call/SMS rows first; the timeline follows.
          if (_needsManualHelp) ...[
            if (help != null) ...[
              NavyHelpCard(key: const Key('dispatch_help'), text: help),
              if (_watchingForLateClaim)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Still checking: a driver can accept until '
                    '${clockTime(context, _lateClaimUntil!.toLocal())}.',
                    key: const Key('dispatch_late_claim_watch'),
                    style: text.bodySmall?.copyWith(color: YomaColors.grey700),
                  ),
                ),
            ],
            if (showContacts) ...[
              const SizedBox(height: 12),
              ManualContactsPanel(
                key: ValueKey(_facilityId),
                facilityIds: {if (_facilityId != null) _facilityId!},
                launcher: _launchContact,
              ),
            ],
            const SizedBox(height: 24),
          ],
          // Lets tests and tools see which status this screen is showing.
          KeyedSubtree(
            key: Key('dispatch_status_${_status.toUpperCase()}'),
            child: DispatchTimelineView(steps: timeline.steps),
          ),
          if (_divertedFrom != null) const SizedBox.shrink(key: Key('dispatch_diverted')),
          if (_showContacts && !_needsManualHelp) ...[
            const SizedBox(height: 16),
            ManualContactsPanel(
              key: ValueKey(_facilityId),
              facilityIds: {if (_facilityId != null) _facilityId!},
              launcher: _launchContact,
            ),
          ],
          if (timeline.waitingForDriver && !_showContacts && !_needsManualHelp)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('dispatch_call_instead'),
                onPressed: () => setState(() => _showContacts = true),
                child: const Text('Call a driver instead'),
              ),
            ),
          const SizedBox(height: 24),
          if (_canCancel) ...[
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                key: const Key('dispatch_cancel'),
                style: TextButton.styleFrom(
                  foregroundColor: YomaColors.grey700,
                  minimumSize: const Size(160, YomaSizes.minTap),
                ),
                onPressed: _cancelling ? null : _confirmCancel,
                child: Text(_cancelling ? 'Cancelling…' : 'Cancel referral'),
              ),
            ),
          ],
          // Quiet, at the bottom: Android back does the same.
          Center(
            child: TextButton(
              key: const Key('dispatch_back_home'),
              style: TextButton.styleFrom(minimumSize: const Size(160, YomaSizes.minTap)),
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Back to Home'),
            ),
          ),
        ],
      ),
    );
  }
}
