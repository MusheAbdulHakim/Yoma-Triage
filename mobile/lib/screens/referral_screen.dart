import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models/emergency_type.dart';
import '../models/facility_catalog.dart';
import '../models/referral.dart';
import '../services/api_client.dart';
import '../services/catalog_store.dart';
import '../services/cho_store.dart';
import '../services/geo.dart';
import '../services/moews_calculator.dart';
import '../services/offline_queue.dart';
import '../services/patient_token.dart';
import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import '../widgets/yoma_components.dart';
import 'dispatch_status_screen.dart';
import 'facility_picker_screen.dart';
import 'failed_referrals_screen.dart';
import 'queued_referral_screen.dart';
import 'vitals_screen.dart';

class ReferralScreen extends StatefulWidget {
  final String? aiScreenResult;
  final double? aiConfidence;
  final String? aiModelVersion;
  final Map<String, Object?>? initialVitals;

  /// Test seams.
  final OfflineQueue? queue;
  final ApiClient? api;

  const ReferralScreen({
    super.key,
    this.aiScreenResult,
    this.aiConfidence,
    this.aiModelVersion,
    this.initialVitals,
    this.queue,
    this.api,
  });

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _formKey = GlobalKey<FormState>();

  /// The vitals for this referral, entered on Record vitals only (from the vitals step,
  /// or via the summary row). Null until recorded.
  late Map<String, Object?>? _vitals = widget.initialVitals;

  String? _emergencyType;
  bool _submitting = false;
  String? _error;
  String? _skipError;

  late final OfflineQueue _queue = widget.queue ?? OfflineQueue.shared;
  late final ApiClient _api = widget.api ?? ApiClient();
  final _catalogStore = CatalogStore();

  static const _notSetUp = 'This phone is not set up as a CHO, so it cannot send a referral. '
      'Call the driver and hospital directly.';

  late final Future<void> _catalogReady;
  ReferralGraph? _graph;
  CatalogFacility? _selectedFacility;
  ChoIdentity? _identity;
  String _originBanner = 'Using Home CHPS location';
  double? _originLat;
  double? _originLon;
  String _originSource = 'home_chps';
  bool _facilityConfirmed = false;

  @override
  void initState() {
    super.initState();
    _catalogReady = unawaitedLoadCatalog();
  }

  Future<void> unawaitedLoadCatalog() async {
    try {
      final identity = await ChoStore().load();
      if (!mounted) return;
      setState(() {
        _identity = identity;
      });
      final graph = await _catalogStore.load();
      final home = identity == null ? null : graph.compoundById(identity.compoundId);
      int? preferredId;
      for (final link in graph.preferredLinks) {
        if (link.chpsCompoundId == identity?.compoundId) {
          preferredId = link.facilityId;
          break;
        }
      }
      final suggested = preferredId != null
          ? graph.facilityById(preferredId)
          : (graph.facilities.isEmpty ? null : graph.facilities.first);

      if (!mounted) return;
      setState(() {
        _graph = graph;
        _originLat = home?.latitude ?? identity?.latitude;
        _originLon = home?.longitude ?? identity?.longitude;
        _originSource = 'home_chps';
        _originBanner = 'Using Home CHPS location';
        _selectedFacility = suggested;
        _facilityConfirmed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The facility list could not be loaded on this phone, so '
            '${FacilityConfig.facilityLabel} is selected. Check the facility before '
            'sending.';
        _selectedFacility = const CatalogFacility(
          id: FacilityConfig.facilityId,
          name: FacilityConfig.facilityLabel,
          latitude: null,
          longitude: null,
          district: 'Tamale Metropolitan',
          hasMaternity: true,
          hasIcu: true,
          type: 'teaching_hospital',
        );
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openPicker() async {
    // An early tap on a slow phone waits for the catalog instead of doing nothing.
    await _catalogReady;
    if (!mounted) return;
    final graph = _graph;
    if (graph == null) return;
    final originLat = _originLat;
    final originLon = _originLon;
    // Without a known location, list by name: this must never block a referral.
    final ranked = originLat == null || originLon == null
        ? listByName(facilities: graph.facilities)
        : rankNearest(
            originLat: originLat,
            originLon: originLon,
            facilities: graph.facilities,
          );
    final picked = await Navigator.of(context).push<CatalogFacility>(
      MaterialPageRoute(
        builder: (_) => FacilityPickerScreen(
          ranked: ranked,
          selectedFacilityId: _selectedFacility?.id,
          originBanner: _originBanner,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedFacility = picked;
        _facilityConfirmed = true;
        _error = null;
        _skipError = null;
      });
    }
  }

  /// One tap: needs only the emergency type and facility, never vitals or a name.
  Future<void> _skipVitals() async {
    await _catalogReady;
    if (!mounted) return;
    final problem = _identity == null
        ? _notSetUp
        : _emergencyType == null
            ? 'Choose the emergency type first'
            : !_facilityConfirmed || _selectedFacility == null
                ? 'Tap above to choose the receiving facility first'
                : null;
    if (problem != null) {
      setState(() => _skipError = problem);
      return;
    }
    await _send(vitalsTaken: false);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await _catalogReady;
    if (!mounted) return;
    if (_identity == null) {
      setState(() => _error = _notSetUp);
      return;
    }
    if (_selectedFacility == null || !_facilityConfirmed) {
      setState(() {
        _error = 'Choose receiving facility (manual confirmation required before submit)';
      });
      return;
    }
    if (_vitals == null) {
      // The button sends without vitals in that case; this is only a guard.
      await _skipVitals();
      return;
    }
    await _send(vitalsTaken: true);
  }

  Future<void> _send({required bool vitalsTaken}) async {
    setState(() {
      _submitting = true;
      _error = null;
      _skipError = null;
    });

    final clientRequestId = const Uuid().v4();
    final token = patientToken();
    int? dispatchId;

    try {
      final req = ReferralRequest(
        clientRequestId: clientRequestId,
        chpsCompoundId: _identity!.compoundId,
        choPhone: _identity!.phone,
        facilityId: _selectedFacility!.id,
        patientHash: token,
        emergencyType: _emergencyType!,
        vitalsTaken: vitalsTaken,
        vitals: !vitalsTaken
            ? const <String, dynamic>{}
            : {
                for (final key in _vitalKeys) key: _vitals?[key],
              },
        aiScreenResult: widget.aiScreenResult,
        aiConfidence: widget.aiConfidence,
        aiModelVersion: widget.aiModelVersion,
        catalogVersion: _graph?.version,
        originLat: _originLat,
        originLon: _originLon,
        originSource: _originSource,
      );

      await _queue.enqueue(req);

      try {
        final res = await _api.createReferral(req);
        dispatchId = OfflineQueue.parseDispatchIdFromResponse(res);
        if (dispatchId != null) {
          await _queue.saveDispatchId(clientRequestId, dispatchId);
        }
        await _queue.flush(_api);
        dispatchId ??= await _queue.lookupDispatchId(clientRequestId);
      } on ApiException catch (e) {
        if (e.isPermanent) {
          await _queue.markFailed(clientRequestId, e.reason);
          if (!mounted) return;
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => FailedReferralsScreen(queue: _queue),
            ),
          );
          return;
        }
        // Anything else: the referral stays queued for retry.
        if (e.needsRetryWarning) _queue.noteRetryWarning(e.retryWarning);
      } catch (_) {
        // Offline / API down — the referral remains durably queued.
      }

      if (!mounted) return;
      if (dispatchId == null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => QueuedReferralScreen(
              clientRequestId: clientRequestId,
              queue: _queue,
              api: _api,
              facilityId: _selectedFacility?.id,
            ),
          ),
        );
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DispatchStatusScreen(
              dispatchId: dispatchId,
              clientRequestId: clientRequestId,
              facilityId: _selectedFacility?.id,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'This referral could not be saved on the phone, so it was not '
              'sent. Phone a driver and the hospital directly now, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facilityLabel = _selectedFacility?.name ?? FacilityConfig.facilityLabel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency referral'),
      ),
      // The button bar is part of the body, not bottomNavigationBar, so it rides above the
      // keyboard instead of being hidden by it (round-6 device pass).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _SectionLabel('Emergency type'),
                  FormField<String>(
                    key: ValueKey('referral_type_$_emergencyType'),
                    initialValue: _emergencyType,
                    validator: (v) => v == null ? 'Choose the emergency type' : null,
                    builder: (field) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = 10.0;
                            final width = (constraints.maxWidth - gap) / 2;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                // The app's current list of types, unchanged.
                                for (final (value, label) in emergencyTypes)
                                  SizedBox(
                                    width: width,
                                    child: YomaChoiceChip(
                                      key: Key('referral_type_$value'),
                                      label: label,
                                      selected: field.value == value,
                                      semanticsHint: 'Emergency type',
                                      minHeight: YomaSizes.chipLarge,
                                      onTap: () {
                                        field.didChange(value);
                                        setState(() {
                                          _emergencyType = value;
                                          _skipError = null;
                                        });
                                      },
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        if (field.hasError)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              field.errorText!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: YomaColors.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('Send to'),
                  Semantics(
                    button: true,
                    label: _facilityConfirmed
                        ? 'Send to $facilityLabel, confirmed. Tap to change.'
                        : 'Send to $facilityLabel. Tap to confirm facility.',
                    excludeSemantics: true,
                    child: Material(
                      color: YomaColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YomaRadii.md),
                        side: BorderSide(
                          color: _facilityConfirmed ? YomaColors.grey300 : YomaColors.brand,
                          width: _facilityConfirmed ? 1 : 2,
                        ),
                      ),
                      child: InkWell(
                        key: const Key('referral_send_to'),
                        borderRadius: BorderRadius.circular(YomaRadii.md),
                        onTap: _openPicker,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        facilityLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                                      ),
                                      // Only until the CHO has confirmed the facility.
                                      if (!_facilityConfirmed)
                                        Text(
                                          'Tap to confirm',
                                          key: const Key('referral_send_to_confirm'),
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: YomaColors.tertiary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.expand_more, color: YomaColors.grey600),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.aiScreenResult case final label?)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        switch (label.toUpperCase()) {
                          notScreenedLabel => 'No breathing check – the hospital will be told',
                          'RED' => 'Breathing check (advisory): Possible breathing problem',
                          _ => "Breathing check (advisory): Couldn't tell",
                        },
                        key: const Key('referral_breathing_note'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: YomaColors.grey700),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _vitalsSummary(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: YomaColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: YomaColors.surface,
              border: Border(top: BorderSide(color: YomaColors.grey100)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_skipError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _skipError!,
                          key: const Key('referral_skip_error'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: YomaColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    // One button. With vitals it sends them; without, it uses the one-tap
                    // skip-vitals path and the hospital is told vitals were not taken.
                    FilledButton(
                      key: const Key('referral_send'),
                      // Grey until an emergency type is chosen; every other check runs on tap.
                      onPressed: _submitting || _emergencyType == null
                          ? null
                          : (_vitals == null ? _skipVitals : _submit),
                      child: Text(
                        _submitting
                            ? 'Sending…'
                            : _vitals == null
                                ? 'Send now (vitals not taken)'
                                : 'Send referral',
                      ),
                    ),
                    if (_emergencyType == null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Choose the emergency type to send',
                          key: const Key('referral_send_hint'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: YomaColors.grey700),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _vitalKeys = [
    'systolic_bp',
    'diastolic_bp',
    'heart_rate',
    'respiratory_rate',
    'temperature',
    'spo2',
    'consciousness_level',
  ];

  /// Opens Record vitals with the current values; what it saves comes back here.
  Future<void> _editVitals() async {
    final saved = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => VitalsScreen(
          result: moewsOnlyResult(),
          initialVitals: _vitals,
          returnVitals: true,
        ),
      ),
    );
    if (saved != null && mounted) {
      setState(() {
        _vitals = saved;
        _error = null;
      });
    }
  }

  /// One line: the risk level of the recorded vitals (scored by the app's MOEWS), or
  /// "Not recorded". Tapping it opens Record vitals; vitals are entered there only.
  Widget _vitalsSummary() {
    final v = _vitals;
    final text = Theme.of(context).textTheme;
    Widget trailing;
    String spoken;
    if (v == null) {
      trailing = Text.rich(
        TextSpan(
          text: 'Not recorded – ',
          style: text.labelMedium?.copyWith(color: YomaColors.grey700),
          children: [
            TextSpan(
              text: 'Record vitals',
              style: text.labelMedium?.copyWith(color: YomaColors.tertiary),
            ),
          ],
        ),
        textAlign: TextAlign.end,
      );
      spoken = 'Vitals: not recorded. Tap to record vitals.';
    } else {
      final moews = calculateMoews(
        sbp: v['systolic_bp'] as int?,
        dbp: v['diastolic_bp'] as int?,
        hr: v['heart_rate'] as int?,
        rr: v['respiratory_rate'] as int?,
        temp: (v['temperature'] as num?)?.toDouble(),
        spo2: v['spo2'] as int?,
        consciousness: v['consciousness_level'] as String?,
      );
      final level = TriageLevel.fromMoews(moews.riskLevel) ?? TriageLevel.incomplete;
      final score = level == TriageLevel.incomplete ? null : moews.score;
      trailing = RiskBadge(level: level, score: score);
      spoken = 'Vitals: ${level.word}${score == null ? '' : ', score $score'}. '
          'Tap to change vitals.';
    }
    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      child: Material(
        color: YomaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YomaRadii.md),
          side: const BorderSide(color: YomaColors.grey200),
        ),
        child: InkWell(
          key: const Key('referral_vitals_summary'),
          borderRadius: BorderRadius.circular(YomaRadii.md),
          onTap: _editVitals,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Text('Vitals:', style: text.labelMedium),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(alignment: Alignment.centerRight, child: trailing),
                  ),
                  const Icon(Icons.chevron_right, color: YomaColors.grey600),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}
