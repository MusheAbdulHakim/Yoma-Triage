import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api_client.dart';
import '../services/catalog_store.dart';
import '../services/offline_queue.dart';
import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import 'failed_referrals_screen.dart';
import 'referral_screen.dart';
import 'screening_screen.dart';
import 'vitals_screen.dart';

class HomeScreen extends StatefulWidget {
  /// Overrides [ScreeningConfig.moewsOnly] so tests can exercise both modes.
  final bool? acousticEnabled;

  const HomeScreen({super.key, this.acousticEnabled});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _catalog = CatalogStore();
  final _queue = OfflineQueue.shared;
  bool _catalogStale = false;
  String? _catalogVersion;
  bool _syncing = false;

  bool get _acousticEnabled =>
      widget.acousticEnabled ?? !ScreeningConfig.moewsOnly;

  @override
  void initState() {
    super.initState();
    _refreshCatalogStatus();
    _syncCatalog();
    // Picks up referrals refused in an earlier session.
    _queue.failed().catchError((_) => <QueuedReferral>[]);
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
    await _catalog.trySyncOnConnect(ApiClient());
    if (!mounted) return;
    setState(() => _syncing = false);
    await _refreshCatalogStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yoma Triage'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (AppEnvironment.name != 'production')
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Env: ${AppEnvironment.name} · model: ${ScreeningConfig.moewsOnly ? 'MOEWS_ONLY' : ScreeningConfig.model}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
            ValueListenableBuilder<int>(
              valueListenable: _queue.failedCount,
              builder: (context, count, _) {
                if (count == 0) return const SizedBox.shrink();
                return Card(
                  color: YomaColors.danger.withValues(alpha: 0.15),
                  child: ListTile(
                    key: const Key('home_failed_referrals'),
                    leading: const Icon(Icons.error, color: YomaColors.danger),
                    title: Text(
                      count == 1
                          ? '1 referral was NOT sent'
                          : '$count referrals were NOT sent',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text('Tap to see why. Call manually.'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FailedReferralsScreen(queue: _queue),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_catalogStale)
              Card(
                color: YomaColors.caution.withValues(alpha: 0.15),
                child: ListTile(
                  title: const Text('Facility catalog may be stale'),
                  subtitle: Text(
                    _catalogVersion == null
                        ? 'Using on-device bootstrap. Sync when online (refresh every ${CatalogConfig.staleAfterDays} days).'
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
            const Spacer(),
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
                child:
                    Text(_acousticEnabled ? 'Screen Breathing' : 'Record Vitals'),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: 'Emergency Referral',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
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
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
