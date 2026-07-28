import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../models/referral.dart';
import '../services/api_client.dart';
import '../services/offline_queue.dart';
import '../services/patient_token.dart';
import '../theme/yoma_theme.dart';
import 'dispatch_status_screen.dart';
import 'queued_referral_screen.dart';

class ReferralScreen extends StatefulWidget {
  final String? aiScreenResult;
  final double? aiConfidence;
  final Map<String, Object>? initialVitals;

  const ReferralScreen({
    super.key,
    this.aiScreenResult,
    this.aiConfidence,
    this.initialVitals,
  });

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _formKey = GlobalKey<FormState>();
  final _patientName = TextEditingController(text: 'Ama Mensah');
  late final TextEditingController _sbp;
  late final TextEditingController _dbp;
  late final TextEditingController _hr;
  late final TextEditingController _rr;
  late final TextEditingController _temp;
  late final TextEditingController _spo2;

  late String _avpu;
  String _emergencyType = 'respiratory_distress';
  bool _submitting = false;
  String? _error;

  final _queue = OfflineQueue.shared;
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    final vitals = widget.initialVitals;
    _sbp = TextEditingController(
      text: (vitals?['systolic_bp'] ?? 70).toString(),
    );
    _dbp = TextEditingController(
      text: (vitals?['diastolic_bp'] ?? 50).toString(),
    );
    _hr = TextEditingController(
      text: (vitals?['heart_rate'] ?? 140).toString(),
    );
    _rr = TextEditingController(
      text: (vitals?['respiratory_rate'] ?? 35).toString(),
    );
    _temp = TextEditingController(
      text: (vitals?['temperature'] ?? 39.5).toString(),
    );
    _spo2 = TextEditingController(
      text: (vitals?['spo2'] ?? 85).toString(),
    );
    _avpu = (vitals?['consciousness_level'] ?? 'V').toString();
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

  int? _parseInt(String raw) => int.tryParse(raw.trim());
  double? _parseDouble(String raw) => double.tryParse(raw.trim());

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final clientRequestId = const Uuid().v4();
    final token = patientToken();
    int? dispatchId;

    try {
      final sbp = _parseInt(_sbp.text);
      final dbp = _parseInt(_dbp.text);
      final hr = _parseInt(_hr.text);
      final rr = _parseInt(_rr.text);
      final temp = _parseDouble(_temp.text);
      final spo2 = _parseInt(_spo2.text);
      if (sbp == null ||
          dbp == null ||
          hr == null ||
          rr == null ||
          temp == null ||
          spo2 == null) {
        throw const FormatException('Invalid vitals');
      }

      final req = ReferralRequest(
        clientRequestId: clientRequestId,
        chpsCompoundId: FacilityConfig.chpsCompoundId,
        facilityId: FacilityConfig.facilityId,
        patientHash: token,
        patientName: _patientName.text.trim(),
        emergencyType: _emergencyType,
        vitals: {
          'systolic_bp': sbp,
          'diastolic_bp': dbp,
          'heart_rate': hr,
          'respiratory_rate': rr,
          'temperature': temp,
          'spo2': spo2,
          'consciousness_level': _avpu,
        },
        aiScreenResult: widget.aiScreenResult,
        aiConfidence: widget.aiConfidence,
      );

      // Persist first so retries keep the same client_request_id + patient_hash.
      await _queue.enqueue(req);

      try {
        final res = await _api.createReferral(req);
        dispatchId = OfflineQueue.parseDispatchIdFromResponse(res);
        if (dispatchId != null) {
          await _queue.saveDispatchId(clientRequestId, dispatchId);
        }
        await _queue.flush(_api);
        dispatchId ??= await _queue.lookupDispatchId(clientRequestId);
      } catch (_) {
        // Offline / API down — the referral remains durably queued.
      }

      if (!mounted) return;
      if (dispatchId == null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => QueuedReferralScreen(
              clientRequestId: clientRequestId,
            ),
          ),
        );
      } else {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DispatchStatusScreen(
              dispatchId: dispatchId,
              clientRequestId: clientRequestId,
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
              child: const ListTile(
                title: Text(FacilityConfig.chpsLabel),
                subtitle: Text('→ ${FacilityConfig.facilityLabel}'),
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
            TextFormField(
              controller: _patientName,
              decoration: const InputDecoration(
                labelText: 'Patient name (local only)',
                helperText: 'Not sent over network — unlinkable token used',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(_emergencyType),
              initialValue: _emergencyType,
              decoration: const InputDecoration(labelText: 'Emergency type'),
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
                setState(() => _emergencyType = v);
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Vitals',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            _numField(_sbp, 'Systolic BP', key: const Key('referral_sbp')),
            _numField(_dbp, 'Diastolic BP', key: const Key('referral_dbp')),
            _numField(_hr, 'Heart rate', key: const Key('referral_hr')),
            _numField(_rr, 'Respiratory rate', key: const Key('referral_rr')),
            _numField(
              _temp,
              'Temperature',
              key: const Key('referral_temp'),
              decimal: true,
            ),
            _numField(_spo2, 'SpO2', key: const Key('referral_spo2')),
            DropdownButtonFormField<String>(
              key: ValueKey(_avpu),
              initialValue: _avpu,
              decoration: const InputDecoration(labelText: 'AVPU'),
              items: const [
                DropdownMenuItem(value: 'A', child: Text('A — Alert')),
                DropdownMenuItem(value: 'V', child: Text('V — Voice')),
                DropdownMenuItem(value: 'P', child: Text('P — Pain')),
                DropdownMenuItem(value: 'U', child: Text('U — Unresponsive')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _avpu = v);
              },
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

  Widget _numField(
    TextEditingController c,
    String label, {
    Key? key,
    bool decimal = false,
  }) {
    return TextFormField(
      key: key,
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (decimal) {
          if (double.tryParse(v.trim()) == null) return 'Invalid number';
        } else if (int.tryParse(v.trim()) == null) {
          return 'Invalid integer';
        }
        return null;
      },
    );
  }
}
