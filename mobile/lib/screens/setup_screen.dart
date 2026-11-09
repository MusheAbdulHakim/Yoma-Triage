import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/yoma_theme.dart';
import '../services/api_client.dart';
import '../services/cho_store.dart';
import '../services/contacts_store.dart';
import '../services/offline_queue.dart';
import '../widgets/dispatch_timeline_view.dart' show NavyHelpCard;
import '../widgets/manual_contacts_panel.dart';
import '../widgets/yoma_components.dart';
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

  /// Set once the server has confirmed the number: the CHO checks the clinic, then Start.
  ChoIdentity? _confirmed;

  /// Ghana mobile numbers have 9 digits after +233. A leading 0 (024…) or a pasted
  /// +233 is accepted and dropped.
  static const localDigits = 9;

  String get _local {
    var digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('233') && digits.length == 12) digits = digits.substring(3);
    if (digits.startsWith('0') && digits.length == 10) digits = digits.substring(1);
    return digits;
  }

  // After +233 a Ghana number never starts with 0.
  bool get _complete => _local.length == localDigits && !_local.startsWith('0');

  @override
  void initState() {
    super.initState();
    _phone.addListener(() => setState(() {}));
    _loadReturnState();
  }

  /// A phone sent back here may still hold referrals the CHO must not lose sight of.
  Future<void> _loadReturnState() async {
    // The notice first, on its own: it says why the CHO is back here, and must not wait on
    // the local queue.
    final notice = await _store.loadNotice();
    if (!mounted) return;
    setState(() => _notice = notice);
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
    if (!_complete) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? error;
    ChoIdentity? identity;
    try {
      identity = ChoIdentity.fromJson(await _api.lookupCho('+233$_local'));
      // Contacts are fetched now, while there is signal, in case it's gone by the next
      // emergency. The identity itself is saved when the CHO taps Start.
      unawaited(ContactsStore().refresh(_api, identity.compoundId));
    } on ApiException catch (e) {
      error = switch (e) {
        _ when e.code == 'CHO_NOT_REGISTERED' =>
          "This number isn't registered. Ask your district coordinator.",
        _ when e.statusCode >= 500 => 'The server is having a problem. Try again shortly.',
        _ when e.code == null => unreachable,
        _ => e.reason,
      };
    } catch (_) {
      error = unreachable;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
      _confirmed = identity;
    });
  }

  /// No connection, or a Wi-Fi login page in the way.
  static const unreachable = "Can't reach the server. Check your signal and try again.";

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final confirmed = _confirmed;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Text('Yoma Care', style: text.headlineMedium?.copyWith(color: YomaColors.primary)),
            const SizedBox(height: 4),
            Text(
              confirmed == null
                  ? 'Enter the phone number registered for your clinic.'
                  : 'Your clinic',
              style: text.bodyMedium?.copyWith(color: YomaColors.grey700),
            ),
            const SizedBox(height: 20),
            // Sent back here by a sync: deactivated, or moved to another compound.
            if (_notice != null) ...[
              NavyHelpCard(key: const Key('setup_notice'), text: _notice!),
              const SizedBox(height: 12),
            ],
            if (_unsentCount > 0) ...[
              StatusStrip(
                stripKey: const Key('setup_unsent'),
                title: countOfReferrals(_unsentCount),
                subtitle: _expiringCount > 0
                    ? 'Tap to see them, and to Call or SMS. '
                        '$_expiringCount will soon be deleted from this phone.'
                    : 'Tap to see them, and to Call or SMS.',
                dark: true,
                expanded: false,
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
              const SizedBox(height: 16),
            ],
            if (confirmed == null) ..._enterNumber(text) else ..._clinicConfirmed(text, confirmed),
          ],
        ),
      ),
    );
  }

  /// State 1: the number, with +233 shown, and Continue once it is complete.
  List<Widget> _enterNumber(TextTheme text) => [
        TextField(
          key: const Key('setup_phone'),
          controller: _phone,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            // 9 digits, 10 with a leading 0, or 12 when a +233 number is pasted.
            LengthLimitingTextInputFormatter(12),
          ],
          autofillHints: const [AutofillHints.telephoneNumberNational],
          style: text.titleLarge,
          decoration: InputDecoration(
            // Names the field for screen readers; never floats over the prefix.
            labelText: 'Phone number, after +233',
            floatingLabelBehavior: FloatingLabelBehavior.never,
            labelStyle: text.titleLarge?.copyWith(color: YomaColors.grey500),
            prefixIcon: Container(
              margin: const EdgeInsets.only(left: 14, right: 12),
              padding: const EdgeInsets.only(right: 12),
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: YomaColors.grey300)),
              ),
              child: ExcludeSemantics(
                child: Text('+233', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minHeight: 56),
            fillColor: YomaColors.surface,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YomaRadii.md),
              borderSide: const BorderSide(color: YomaColors.grey300, width: 2),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('setup_continue'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          // Disabled until the number is complete.
          onPressed: _submitting || !_complete ? null : _submit,
          child: Text(_submitting ? 'Checking…' : 'Continue'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          NavyHelpCard(key: const Key('setup_error'), text: _error!),
        ],
      ];

  /// State 2: the server's clinic for this number, and Start.
  List<Widget> _clinicConfirmed(TextTheme text, ChoIdentity identity) => [
        YomaCard(
          key: const Key('setup_confirmed'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration:
                        const BoxDecoration(color: YomaColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 18, color: YomaColors.onPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      identity.compoundName,
                      key: const Key('setup_clinic_name'),
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(
                key: const Key('setup_start'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  await _store.save(identity);
                  widget.onComplete(identity);
                },
                child: const Text('Start'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Not in the design: a way back if the clinic shown is not theirs.
        Center(
          child: TextButton(
            key: const Key('setup_change_number'),
            onPressed: () => setState(() => _confirmed = null),
            child: const Text('Not your clinic? Use a different number'),
          ),
        ),
      ];
}

String countOfReferrals(int n) =>
    n == 1 ? '1 referral has not reached a driver' : '$n referrals have not reached a driver';
