import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../release_settings.dart';
import '../services/api_client.dart';
import '../services/catalog_store.dart';
import '../services/cho_store.dart';
import '../services/contacts_store.dart';
import '../services/offline_queue.dart';
import '../services/friendly_time.dart';
import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import '../widgets/ambulance_icon.dart';
import '../widgets/yoma_components.dart';
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

  /// Test seam: whether the phone has a network, instead of connectivity_plus.
  final Stream<bool>? online;

  const HomeScreen({super.key, this.acousticEnabled, this.api, this.queue, this.online});

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
  String? _compoundName;

  /// No network on this phone (no Wi-Fi, no mobile data). Unknown counts as online, so
  /// the pill never shows by mistake.
  bool _offline = false;
  StreamSubscription<bool>? _onlineSub;

  bool get _acousticEnabled => widget.acousticEnabled ?? !ScreeningConfig.moewsOnly;

  @override
  void initState() {
    super.initState();
    _watchConnectivity();
    _loadCompoundName();
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
    unawaited(_onlineSub?.cancel());
    _queue.needsConfirmationCount.removeListener(_onStaleCountChanged);
    super.dispose();
  }

  /// The same rule as the queue's sync: offline only when every connection is none.
  void _watchConnectivity() {
    Stream<bool> online;
    if (widget.online != null) {
      online = widget.online!;
    } else {
      final connectivity = Connectivity();
      bool isOnline(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);
      online = (() async* {
        try {
          yield isOnline(await connectivity.checkConnectivity());
          yield* connectivity.onConnectivityChanged.map(isOnline);
        } catch (_) {
          // No connectivity plugin (tests, web): say nothing rather than guess.
        }
      })();
    }
    _onlineSub = online.listen(
      (value) {
        if (mounted && _offline == value) setState(() => _offline = !value);
      },
      onError: (_) {},
    );
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

  Future<void> _loadCompoundName() async {
    final identity = await ChoStore().load().catchError((_) => null);
    if (!mounted || identity == null) return;
    setState(() => _compoundName = identity.compoundName);
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
            item: StatusStripItem(
              key: const Key('home_failed_referrals'),
              urgent: true,
              icon: Icons.error_outline,
              title: _queue.failedCount.value == 1
                  ? '1 referral was NOT sent'
                  : '${_queue.failedCount.value} referrals were NOT sent',
              subtitle: 'Tap to see why. Call manually.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FailedReferralsScreen(queue: _queue),
                ),
              ),
            ),
          ),
        if (_queue.needsConfirmationCount.value > 0)
          _Warning(
            urgent: true,
            title: 'Still needs transport?',
            item: StatusStripItem(
              key: const Key('home_stale_referrals'),
              urgent: true,
              icon: Icons.help_outline,
              title: 'Still needs transport?',
              subtitle: _queue.needsConfirmationCount.value == 1
                  ? '1 old referral is waiting for your answer. '
                      'Drivers have not been told.'
                  : '${_queue.needsConfirmationCount.value} old referrals are waiting '
                      'for your answer. Drivers have not been told.',
              onTap: _openStalePrompt,
            ),
          ),
        if (_queue.expiringCount.value > 0)
          _Warning(
            urgent: false,
            title: _queue.expiringCount.value == 1
                ? '1 unsent referral will soon be deleted'
                : '${_queue.expiringCount.value} unsent referrals will soon be deleted',
            item: StatusStripItem(
              key: const Key('home_expiring'),
              urgent: false,
              icon: Icons.delete_outline,
              title: _queue.expiringCount.value == 1
                  ? '1 unsent referral will soon be deleted from this phone'
                  : '${_queue.expiringCount.value} unsent referrals will soon be deleted '
                      'from this phone',
              subtitle: 'Tap to see them, and to Call or SMS.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UnsentReferralsScreen(queue: _queue, api: widget.api),
                ),
              ),
            ),
          ),
        if (_queue.retryWarning.value case final warning?)
          _Warning(
            urgent: false,
            title: warning,
            item: StatusStripItem(
              key: const Key('home_retry_warning'),
              urgent: false,
              icon: Icons.wifi_off,
              title: warning,
            ),
          ),
        if (_catalogStale)
          _Warning(
            urgent: false,
            title: 'Facility catalog may be stale',
            item: StatusStripItem(
              key: const Key('home_catalog_stale'),
              urgent: false,
              icon: Icons.sync_problem,
              title: 'Facility catalog may be stale',
              subtitle: _catalogVersion == null
                  ? 'Using on-device bootstrap. Sync when online (refresh every '
                      '${CatalogConfig.staleAfterDays} days).'
                  : 'Last version $_catalogVersion. Sync when online.',
              trailing: _syncing
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Sync facility catalog',
                      icon: const Icon(Icons.sync, color: YomaColors.grey800),
                      onPressed: _syncCatalog,
                    ),
            ),
          ),
      ];

  /// One strip for all the warnings, so they can never push Emergency referral off the
  /// screen. It names the most urgent, and opens to show each. Navy when the most urgent
  /// is a failure or needs an answer; light while things are only waiting.
  Widget _warningsSummary(List<_Warning> warnings) {
    final top = warnings.first;
    final more = warnings.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusStrip(
          stripKey: const Key('home_warnings_summary'),
          dark: top.urgent,
          expanded: _warningsOpen,
          // Open, the header names how many; the items below say what they are, so the
          // first one is never repeated in the header.
          title: _warningsOpen ? countOf(warnings.length, 'warning') : top.title,
          subtitle: _warningsOpen
              ? 'Tap to hide'
              : more == 0
                  ? 'Tap to see details'
                  : '$more more ${more == 1 ? 'warning' : 'warnings'}. Tap to see all.',
          onTap: () => setState(() => _warningsOpen = !_warningsOpen),
        ),
        if (_warningsOpen) ...[for (final warning in warnings) warning.item],
      ],
    );
  }

  void _openReferral() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ReferralScreen()),
    );
  }

  void _openBreathCheck() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScreeningScreen()),
    );
  }

  void _openVitals() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VitalsScreen(result: moewsOnlyResult())),
    );
  }

  Widget _topBar(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          YomaSpacing.gutter, YomaSpacing.md, YomaSpacing.gutter, YomaSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Yoma Care',
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_compoundName case final name?)
                  Text(
                    name,
                    key: const Key('home_clinic_name'),
                    style: text.bodyMedium?.copyWith(color: YomaColors.grey700),
                  ),
              ],
            ),
          ),
          if (_offline) const _OfflinePill(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topBar(text),
            // Pinned above everything that scrolls: always on screen, whatever else is.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: YomaSpacing.gutter),
              child: _EmergencyReferralButton(onPressed: _openReferral),
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
                  return CustomScrollView(
                    key: const Key('home_scroll'),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                            YomaSpacing.gutter, YomaSpacing.md, YomaSpacing.gutter, YomaSpacing.lg),
                        sliver: SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_acousticEnabled) ...[
                                _HomeActionButton(
                                  buttonKey: const Key('home_check_breathing'),
                                  icon: Icons.graphic_eq,
                                  label: 'Check breathing',
                                  tag: 'Advisory',
                                  onPressed: _openBreathCheck,
                                ),
                              ] else
                                _HomeActionButton(
                                  buttonKey: const Key('home_record_vitals'),
                                  icon: Icons.monitor_heart_outlined,
                                  label: 'Record vitals',
                                  onPressed: _openVitals,
                                ),
                              const Spacer(),
                              if (warnings.isNotEmpty) ...[
                                const SizedBox(height: YomaSpacing.lg),
                                _warningsSummary(warnings),
                              ],
                              // Test builds only: a small footer, never in the main content.
                              if (yomaTestRelease)
                                Padding(
                                  padding: const EdgeInsets.only(top: YomaSpacing.md),
                                  child: Text(
                                    'Env: ${AppEnvironment.name} · model: '
                                    '${ScreeningConfig.moewsOnly ? 'MOEWS_ONLY' : ScreeningConfig.model}',
                                    key: const Key('home_env_footer'),
                                    textAlign: TextAlign.center,
                                    style: text.labelSmall?.copyWith(color: YomaColors.grey600),
                                  ),
                                ),
                            ],
                          ),
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

/// The teal Emergency referral card. Always the largest and first action on Home.
class _EmergencyReferralButton extends StatelessWidget {
  const _EmergencyReferralButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Emergency referral',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(YomaRadii.lg),
          boxShadow: YomaShadows.sm,
        ),
        child: Material(
          color: YomaColors.brand,
          borderRadius: BorderRadius.circular(YomaRadii.lg),
          child: InkWell(
            key: const Key('home_emergency_referral'),
            borderRadius: BorderRadius.circular(YomaRadii.lg),
            splashColor: YomaColors.brandPressed,
            highlightColor: YomaColors.brandPressed,
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: YomaColors.onPrimary.withValues(alpha: 0.9), width: 2),
                      ),
                      alignment: Alignment.center,
                      child: const AmbulanceIcon(size: 26, color: YomaColors.onPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Emergency referral',
                      textAlign: TextAlign.center,
                      style: text.headlineSmall?.copyWith(color: YomaColors.onPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width outlined action under Emergency referral.
class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tag,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final String? tag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: tag == null ? label : '$label, $tag',
      excludeSemantics: true,
      child: Material(
        color: YomaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YomaRadii.lg),
          side: BorderSide(color: YomaColors.brand.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(YomaRadii.lg),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (tag != null) const SizedBox(width: 4),
                  Expanded(
                    child: Row(
                      mainAxisAlignment:
                          tag == null ? MainAxisAlignment.center : MainAxisAlignment.start,
                      children: [
                        Icon(icon, color: YomaColors.brand, size: 24),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            label,
                            style: text.titleLarge?.copyWith(color: YomaColors.brand),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tag != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: YomaColors.grey100,
                        borderRadius: BorderRadius.circular(YomaRadii.sm - 2),
                        border: Border.all(color: YomaColors.grey200),
                      ),
                      child: Text(
                        tag!,
                        style: text.labelSmall?.copyWith(color: YomaColors.grey700),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A warning on Home: [title] for the summary strip, [item] for the open list.
class _Warning {
  const _Warning({required this.urgent, required this.title, required this.item});

  final bool urgent;
  final String title;
  final Widget item;
}

/// "Offline" when the phone has no network. Referrals still save and send later.
class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('home_offline'),
      container: true,
      liveRegion: true,
      label: 'Offline. Referrals are saved and sent when there is signal.',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(left: 8, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: YomaColors.grey200,
          borderRadius: BorderRadius.circular(YomaRadii.pill),
          border: Border.all(color: YomaColors.grey300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 14, color: YomaColors.grey700),
            const SizedBox(width: 6),
            Text(
              'Offline',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: YomaColors.grey800),
            ),
          ],
        ),
      ),
    );
  }
}
