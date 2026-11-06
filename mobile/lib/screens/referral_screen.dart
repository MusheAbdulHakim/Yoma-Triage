import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models/facility_catalog.dart';
import '../models/referral.dart';
import '../services/api_client.dart';
import '../services/catalog_store.dart';
import '../services/cho_store.dart';
import '../services/geo.dart';
import '../services/offline_queue.dart';
import '../services/patient_token.dart';
import '../services/vital_limits.dart';
import '../theme/yoma_theme.dart';
import '../widgets/vital_field.dart';
import 'dispatch_status_screen.dart';
import 'facility_picker_screen.dart';
import 'failed_referrals_screen.dart';
import 'queued_referral_screen.dart';

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
  final _patientName = TextEditingController();
  late final VitalInput _sbp;
  late final VitalInput _dbp;
  late final VitalInput _hr;
  late final VitalInput _rr;
  late final VitalInput _temp;
  late final VitalInput _spo2;

  String? _avpu;
  String? _emergencyType;
  bool _submitting = false;
  String? _error;
  String? _skipError;

  late final OfflineQueue _queue = widget.queue ?? OfflineQueue.shared;
  late final ApiClient _api = widget.api ?? ApiClient();
  final _catalogStore = CatalogStore();

  static const _notSetUp =
      'This phone is not set up as a CHO, so it cannot send a referral. '
      'Call the driver and hospital directly.';

  late final Future<void> _catalogReady;
  ReferralGraph? _graph;
  CatalogFacility? _selectedFacility;
  ChoIdentity? _identity;
  bool _identityLoaded = false;
  String _originBanner = 'Using Home CHPS location';
  double? _originLat;
  double? _originLon;
  String _originSource = 'home_chps';
  bool _facilityConfirmed = false;

  @override
  void initState() {
    super.initState();
    final vitals = widget.initialVitals;
    _sbp = VitalInput.fromVitals(vitals, 'systolic_bp');
    _dbp = VitalInput.fromVitals(vitals, 'diastolic_bp');
    _hr = VitalInput.fromVitals(vitals, 'heart_rate');
    _rr = VitalInput.fromVitals(vitals, 'respiratory_rate');
    _temp = VitalInput.fromVitals(vitals, 'temperature');
    _spo2 = VitalInput.fromVitals(vitals, 'spo2');
    _avpu = AvpuField.fromVitals(vitals);
    _catalogReady = unawaitedLoadCatalog();
  }

  Future<void> unawaitedLoadCatalog() async {
    try {
      final identity = await ChoStore().load();
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _identityLoaded = true;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Catalog load failed: $e';
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
    _patientName.dispose();
    _sbp.dispose();
    _dbp.dispose();
    _hr.dispose();
    _rr.dispose();
    _temp.dispose();
    _spo2.dispose();
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
        _error =
            'Choose receiving facility (manual confirmation required before submit)';
      });
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
        patientName: _patientName.text.trim(),
        emergencyType: _emergencyType!,
        vitalsTaken: vitalsTaken,
        vitals: !vitalsTaken
            ? const <String, dynamic>{}
            : {
                'systolic_bp': _sbp.intValue,
                'diastolic_bp': _dbp.intValue,
                'heart_rate': _hr.intValue,
                'respiratory_rate': _rr.intValue,
                'temperature': _temp.doubleValue,
                'spo2': _spo2.intValue,
                'consciousness_level': AvpuField.apiValue(_avpu),
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
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not queue referral: $e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final facilityLabel =
        _selectedFacility?.name ?? FacilityConfig.facilityLabel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Referral — Vitals'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: YomaColors.brand.withValues(alpha: 0.08),
              child: ListTile(
                title: Text(
                  _identity?.compoundName ??
                      (_identityLoaded ? 'This phone is not set up' : '…'),
                ),
                subtitle: Text(
                  _facilityConfirmed
                      ? '→ $facilityLabel (confirmed)'
                      : '→ $facilityLabel (tap to confirm facility)',
                ),
                trailing: const Icon(Icons.edit_location_alt),
                onTap: _openPicker,
              ),
            ),
            if (!_facilityConfirmed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _originBanner,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ),
            if (widget.aiScreenResult != null)
              Card(
                color: Colors.blue.shade50,
                child: ListTile(
                  title: Text('AI screen: ${widget.aiScreenResult}'),
                  subtitle: Text(
                    'Confidence: ${((widget.aiConfidence ?? 0) * 100).toStringAsFixed(0)}%',
                  ),
                ),
              ),
            DropdownButtonFormField<String>(
              key: ValueKey(_emergencyType),
              initialValue: _emergencyType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Emergency type'),
              validator: (v) => v == null ? 'Choose the emergency type' : null,
              items: const [
                DropdownMenuItem(
                  value: 'respiratory_distress',
                  child: Text('Respiratory distress'),
                ),
                DropdownMenuItem(
                  value: 'pph',
                  child: Text('Postpartum hemorrhage'),
                ),
                DropdownMenuItem(
                  value: 'neonatal_asphyxia',
                  child: Text('Neonatal asphyxia'),
                ),
                DropdownMenuItem(
                  value: 'eclampsia',
                  child: Text('Eclampsia'),
                ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _emergencyType = v;
                  _skipError = null;
                });
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('referral_skip_vitals'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: YomaColors.danger,
                textStyle: const TextStyle(fontSize: 18),
              ),
              onPressed: _submitting ? null : _skipVitals,
              child: const Text('Emergency: skip vitals'),
            ),
            const SizedBox(height: 4),
            Text(
              'Dispatches now. Needs only the emergency type and facility.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            if (_skipError != null) ...[
              const SizedBox(height: 8),
              Text(
                _skipError!,
                key: const Key('referral_skip_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: YomaColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Divider(),
            TextFormField(
              controller: _patientName,
              decoration: const InputDecoration(
                labelText: 'Patient name (local only)',
                hintText: 'Name, or type Unknown',
                helperText: 'Not sent over network — unlinkable token used',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter the name, or type Unknown'
                  : null,
            ),
            const SizedBox(height: 12),
            const Text(
              'Vitals',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            VitalField(
              input: _sbp,
              limits: VitalLimits.systolicBp,
              label: 'Systolic BP',
              fieldKey: 'referral_sbp',
            ),
            VitalField(
              input: _dbp,
              limits: VitalLimits.diastolicBp,
              label: 'Diastolic BP',
              fieldKey: 'referral_dbp',
            ),
            VitalField(
              input: _hr,
              limits: VitalLimits.heartRate,
              label: 'Heart rate',
              fieldKey: 'referral_hr',
            ),
            VitalField(
              input: _rr,
              limits: VitalLimits.respiratoryRate,
              label: 'Respiratory rate',
              fieldKey: 'referral_rr',
            ),
            VitalField(
              input: _temp,
              limits: VitalLimits.temperature,
              label: 'Temperature',
              fieldKey: 'referral_temp',
              decimal: true,
            ),
            VitalField(
              input: _spo2,
              limits: VitalLimits.spo2,
              label: 'SpO2',
              fieldKey: 'referral_spo2',
            ),
            AvpuField(
              key: const Key('referral_avpu'),
              value: _avpu,
              onChanged: (value) => setState(() => _avpu = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.orange)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: YomaColors.danger,
              ),
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Confirm Referral'),
            ),
          ],
        ),
      ),
    );
  }
}
