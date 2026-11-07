import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api_client.dart';
import '../services/catalog_store.dart';
import '../services/cho_store.dart';
import '../services/contacts_store.dart';
import '../services/offline_queue.dart';
import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import 'failed_referrals_screen.dart';
import 'referral_screen.dart';
import 'stale_referral_screen.dart';
import 'unsent_referrals_screen.dart';
import 'screening_screen.dart';
import 'vitals_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Overrides [ScreeningConfig.moewsOnly] so tests can exercise both modes.
  final bool? acousticEnabled;

  /// Test seam for the sync that runs when Home opens.
  final ApiClient? api;
  final OfflineQueue? queue;

  const HomeScreen({super.key, this.acousticEnabled, this.api, this.queue});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _catalog = CatalogStore();
  late final OfflineQueue _queue = widget.queue ?? OfflineQueue.shared;
  int _lastStaleCount = 0;
  bool _catalogStale = false;
  String? _catalogVersion;
  bool _syncing = false;
  bool _warningsOpen = false;

  bool get _acousticEnabled =>
      widget.acousticEnabled ?? !ScreeningConfig.moewsOnly;

  @override
  void initState() {
    super.initState();
    _refreshCatalogStatus();
    _syncCatalog();
    // Picks up referrals refused in an earlier session.
    _queue.failed().catchError((_) => <QueuedReferral>[]);
    _queue.needsConfirmationCount.addListener(_onStaleCountChanged);
    _queue.needsConfirmation().catchError((_) => <QueuedReferral>[]);
    // The CHO can see this screen, so this counts as being warned.
    _queue.noteExpiryWarning().catchError((_) => 0);
  }

  @override
  void dispose() {
    _queue.needsConfirmationCount.removeListener(_onStaleCountChanged);
    super.dispose();
  }

  /// Asks as soon as a stale referral arrives, unless the CHO is busy on another screen.
  /// In that case the card below is waiting for them when they come back.
  void _onStaleCountChanged() {
    final count = _queue.needsConfirmationCount.value;
    final arrived = count > _lastStaleCount;
    _lastStaleCount = count;
    if (arrived && mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      _openStalePrompt();
    }
  }

  void _openStalePrompt() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StaleReferralScreen(queue: _queue, api: widget.api),
      ),
    );
  }

  Future<void> _refreshCatalogStatus() async {
    final stale = await _catalog.isStale();
    final version = await _catalog.cachedVersion();
    if (!mounted) return;
    setState(() {
      _catalogStale = stale;
      _catalogVersion = version;
    });
  }

  Future<void> _syncCatalog() async {
    setState(() => _syncing = true);
    final api = widget.api ?? ApiClient();
    await _catalog.trySyncOnConnect(api);
    await ChoStore().recheck(api);
    await ContactsStore().refreshForThisPhone(api);
    if (!mounted) return;
    setState(() => _syncing = false);
    await _refreshCatalogStatus();
  }

  /// Every warning that applies now, most urgent first.
  List<_Warning> _warnings() => [
        if (_queue.failedCount.value > 0)
          _Warning(
            urgent: true,
            title: _queue.failedCount.value == 1
                ? '1 referral was NOT sent'
                : '${_queue.failedCount.value} referrals were NOT sent',
            card: Card(
              color: YomaColors.danger.withValues(alpha: 0.15),
              child: ListTile(
                key: const Key('home_failed_referrals'),
                leading: const Icon(Icons.error, color: YomaColors.danger),
                title: Text(
                  _queue.failedCount.value == 1
                      ? '1 referral was NOT sent'
                      : '${_queue.failedCount.value} referrals were NOT sent',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Tap to see why. Call manually.'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FailedReferralsScreen(queue: _queue),
                  ),
                ),
              ),
            ),
          ),
        if (_queue.needsConfirmationCount.value > 0)
          _Warning(
            urgent: true,
            title: 'Still needs transport?',
            card: Card(
              color: YomaColors.danger.withValues(alpha: 0.15),
              child: ListTile(
                key: const Key('home_stale_referrals'),
                leading: const Icon(Icons.help, color: YomaColors.danger),
                title: const Text(
                  'Still needs transport?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _queue.needsConfirmationCount.value == 1
                      ? '1 old referral is waiting for your answer. '
                          'Drivers have not been told.'
                      : '${_queue.needsConfirmationCount.value} old referrals are waiting '
                          'for your answer. Drivers have not been told.',
                ),
                onTap: _openStalePrompt,
              ),
            ),
          ),
        if (_queue.expiringCount.value > 0)
          _Warning(
            urgent: false,
            title: _queue.expiringCount.value == 1
                ? '1 unsent referral will soon be deleted'
                : '${_queue.expiringCount.value} unsent referrals will soon be deleted',
            card: Card(
              color: YomaColors.caution.withValues(alpha: 0.15),
              child: ListTile(
                key: const Key('home_expiring'),
                leading: const Icon(Icons.delete_outline, color: YomaColors.caution),
                title: Text(
                  _queue.expiringCount.value == 1
                      ? '1 unsent referral will soon be deleted from this phone'
                      : '${_queue.expiringCount.value} unsent referrals will soon be deleted '
                          'from this phone',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Tap to see them, and to Call or SMS.'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => UnsentReferralsScreen(queue: _queue, api: widget.api),
                  ),
                ),
              ),
            ),
          ),
        if (_queue.retryWarning.value case final warning?)
          _Warning(
            urgent: false,
            title: warning,
            card: Card(
              color: YomaColors.caution.withValues(alpha: 0.15),
              child: ListTile(
                leading: const Icon(Icons.wifi_off, color: YomaColors.caution),
                title: Text(warning, key: const Key('home_retry_warning')),
              ),
            ),
          ),
        if (_catalogStale)
          _Warning(
            urgent: false,
            title: 'Facility catalog may be stale',
            card: Card(
              color: YomaColors.caution.withValues(alpha: 0.15),
              child: ListTile(
                key: const Key('home_catalog_stale'),
                title: const Text('Facility catalog may be stale'),
                subtitle: Text(
                  _catalogVersion == null
                      ? 'Using on-device bootstrap. Sync when online (refresh every '
                          '${CatalogConfig.staleAfterDays} days).'
                      : 'Last version $_catalogVersion. Sync when online.',
                ),
                trailing: _syncing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.sync),
                        onPressed: _syncCatalog,
                      ),
              ),
            ),
          ),
      ];

  /// One banner for all the warnings, so they can never push Emergency Referral off the
  /// screen. It names the most urgent, and opens to show each.
  Widget _warningsSummary(List<_Warning> warnings) {
    final top = warnings.first;
    final colour = top.urgent ? YomaColors.danger : YomaColors.caution;
    final more = warnings.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: colour.withValues(alpha: 0.15),
          child: ListTile(
            key: const Key('home_warnings_summary'),
            leading: Icon(top.urgent ? Icons.error : Icons.warning_amber, color: colour),
            title: Text(top.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              _warningsOpen
                  ? 'Tap to hide'
                  : more == 0
                      ? 'Tap to see details'
                      : '$more more ${more == 1 ? 'warning' : 'warnings'}. Tap to see all.',
            ),
            trailing: Icon(_warningsOpen ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _warningsOpen = !_warningsOpen),
          ),
        ),
        if (_warningsOpen) ...[for (final warning in warnings) warning.card],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yoma Triage'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pinned above everything that scrolls: always on screen, whatever else is.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Semantics(
                button: true,
                label: 'Emergency Referral',
                child: OutlinedButton(
                  key: const Key('home_emergency_referral'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(64),
                    foregroundColor: YomaColors.danger,
                    side: const BorderSide(color: YomaColors.danger, width: 2),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ReferralScreen()),
                    );
                  },
                  child: const Text('Emergency Referral'),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  _queue.failedCount,
                  _queue.needsConfirmationCount,
                  _queue.expiringCount,
                  _queue.retryWarning,
                ]),
                builder: (context, _) {
                  final warnings = _warnings();
                  return ListView(
                    key: const Key('home_scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      if (AppEnvironment.name != 'production')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Env: ${AppEnvironment.name} · model: '
                            '${ScreeningConfig.moewsOnly ? 'MOEWS_ONLY' : ScreeningConfig.model}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ),
                      if (warnings.isNotEmpty) _warningsSummary(warnings),
                      const SizedBox(height: 16),
                      const Text(
                        'Community Health Officer',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _acousticEnabled
                            ? 'Screen breathing or start an emergency referral.'
                            : 'Record vitals or start an emergency referral.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 24),
                      Semantics(
                        button: true,
                        label: _acousticEnabled ? 'Screen Breathing' : 'Record Vitals',
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(72),
                            textStyle: const TextStyle(fontSize: 20),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => _acousticEnabled
                                    ? const ScreeningScreen()
                                    : VitalsScreen(result: moewsOnlyResult()),
                              ),
                            );
                          },
                          child: Text(_acousticEnabled ? 'Screen Breathing' : 'Record Vitals'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A warning on Home: [title] for the summary banner, [card] for the open list.
class _Warning {
  const _Warning({required this.urgent, required this.title, required this.card});

  final bool urgent;
  final String title;
  final Widget card;
}
