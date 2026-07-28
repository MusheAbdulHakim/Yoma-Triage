import 'package:flutter/material.dart';

import '../services/moews_calculator.dart';
import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import 'result_screen.dart';

class VitalsScreen extends StatefulWidget {
  const VitalsScreen({super.key, required this.result});

  final ScreeningResult result;

  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sbp = TextEditingController(text: '120');
  final _dbp = TextEditingController(text: '80');
  final _hr = TextEditingController(text: '80');
  final _rr = TextEditingController(text: '18');
  final _temp = TextEditingController(text: '37.0');
  final _spo2 = TextEditingController(text: '98');
  String _avpu = 'A';
  int _hrScore = 0;

  @override
  void initState() {
    super.initState();
    _hr.addListener(_recomputeHrBand);
    _recomputeHrBand();
  }

  void _recomputeHrBand() {
    final hr = int.tryParse(_hr.text.trim());
    final next = hr == null
        ? 0
        : calculateMoews(
            sbp: 120,
            dbp: 80,
            hr: hr,
            rr: 18,
            temp: 37.0,
            spo2: 98,
            consciousness: 'A',
          ).hrScore;
    if (next != _hrScore) {
      setState(() => _hrScore = next);
    }
  }

  @override
  void dispose() {
    _hr.removeListener(_recomputeHrBand);
    _sbp.dispose();
    _dbp.dispose();
    _hr.dispose();
    _rr.dispose();
    _temp.dispose();
    _spo2.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;

    final vitals = <String, Object>{
      'systolic_bp': int.parse(_sbp.text.trim()),
      'diastolic_bp': int.parse(_dbp.text.trim()),
      'heart_rate': int.parse(_hr.text.trim()),
      'respiratory_rate': int.parse(_rr.text.trim()),
      'temperature': double.parse(_temp.text.trim()),
      'spo2': int.parse(_spo2.text.trim()),
      'consciousness_level': _avpu,
    };
    final moews = calculateMoews(
      sbp: vitals['systolic_bp'] as int,
      dbp: vitals['diastolic_bp'] as int,
      hr: vitals['heart_rate'] as int,
      rr: vitals['respiratory_rate'] as int,
      temp: vitals['temperature'] as double,
      spo2: vitals['spo2'] as int,
      consciousness: vitals['consciousness_level'] as String,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: widget.result,
          moews: moews,
          vitals: vitals,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hrAbnormal = _hrScore > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Record Vitals')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Enter current vitals before viewing the screening result.',
            ),
            const SizedBox(height: 12),
            _numberField(_sbp, 'Systolic BP', const Key('vitals_sbp')),
            _numberField(_dbp, 'Diastolic BP', const Key('vitals_dbp')),
            _numberField(
              _hr,
              'Heart rate',
              const Key('vitals_hr'),
              highlight: hrAbnormal,
              helperText: hrAbnormal
                  ? 'MOEWS HR band elevated (score $_hrScore) — may escalate referral'
                  : 'Normal adult band roughly 60–110 bpm (GHS MOEWS)',
            ),
            _numberField(_rr, 'Respiratory rate', const Key('vitals_rr')),
            _numberField(
              _temp,
              'Temperature',
              const Key('vitals_temp'),
              decimal: true,
            ),
            _numberField(_spo2, 'SpO2', const Key('vitals_spo2')),
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
              onChanged: (value) {
                if (value != null) setState(() => _avpu = value);
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _continue,
            child: const Text('Continue to Result'),
          ),
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    Key key, {
    bool decimal = false,
    bool highlight = false,
    String? helperText,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        filled: highlight,
        fillColor: highlight ? YomaColors.danger.withValues(alpha: 0.08) : null,
        enabledBorder: highlight
            ? const OutlineInputBorder(
                borderSide: BorderSide(color: YomaColors.danger, width: 1.5),
              )
            : null,
      ),
      validator: (value) {
        final raw = value?.trim() ?? '';
        if (raw.isEmpty) return 'Required';
        if (decimal
            ? double.tryParse(raw) == null
            : int.tryParse(raw) == null) {
          return 'Invalid number';
        }
        return null;
      },
    );
  }
}
