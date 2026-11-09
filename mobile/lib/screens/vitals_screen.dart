import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../services/advisory_hr.dart';
import '../services/moews_calculator.dart';
import '../services/screening_result.dart';
import '../services/vital_limits.dart';
import '../theme/yoma_theme.dart';
import '../widgets/vital_field.dart';
import 'result_screen.dart';

class VitalsScreen extends StatefulWidget {
  const VitalsScreen({
    super.key,
    required this.result,
    this.initialVitals,
    this.returnVitals = false,
  });

  final ScreeningResult result;

  /// Values recorded earlier (from the referral form), shown for editing.
  final Map<String, Object?>? initialVitals;

  /// Opened from the referral form: "See result" hands the vitals back to the form
  /// (Navigator.pop) instead of going on to the Result screen. Vitals are entered here only.
  final bool returnVitals;

  @override
  State<VitalsScreen> createState() => _VitalsScreenState();
}

class _VitalsScreenState extends State<VitalsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _sbp = VitalInput.fromVitals(widget.initialVitals, 'systolic_bp');
  late final _dbp = VitalInput.fromVitals(widget.initialVitals, 'diastolic_bp');
  late final _hr = VitalInput.fromVitals(widget.initialVitals, 'heart_rate');
  late final _rr = VitalInput.fromVitals(widget.initialVitals, 'respiratory_rate');
  late final _temp = VitalInput.fromVitals(widget.initialVitals, 'temperature');
  late final _spo2 = VitalInput.fromVitals(widget.initialVitals, 'spo2');
  late String? _avpu = AvpuField.fromVitals(widget.initialVitals);
  int _hrScore = 0;
  AdvisoryHrReading? _advisoryApplied;

  /// One key per card, so "See result" can scroll to the first vital still missing.
  final _cardKeys = {for (final id in _VitalId.values) id: GlobalKey()};

  /// The card "See result" last pointed at; cleared on the next change.
  _VitalId? _flagged;

  @override
  void initState() {
    super.initState();
    _hr.controller.addListener(_recomputeHrBand);
    _recomputeHrBand();
  }

  void _recomputeHrBand() {
    final hr = _hr.intValue;
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
    _hr.controller.removeListener(_recomputeHrBand);
    _sbp.dispose();
    _dbp.dispose();
    _hr.dispose();
    _rr.dispose();
    _temp.dispose();
    _spo2.dispose();
    super.dispose();
  }

  Future<void> _openAdvisoryHrSheet() async {
    final hrCtrl = TextEditingController(text: _hr.controller.text);
    final spo2Ctrl = TextEditingController();
    var source = AdvisoryHrSource.blePulseOx;

    final draft = await showModalBottomSheet<AdvisoryHrReading>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Advisory device HR',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Optional BLE pulse-ox or contact PPG fill-in. '
                    'Does not replace manual vitals or clinical judgment.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AdvisoryHrSource>(
                    initialValue: source,
                    decoration: const InputDecoration(labelText: 'Source'),
                    items: [
                      for (final s in AdvisoryHrSource.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheet(() => source = v);
                    },
                  ),
                  TextField(
                    key: const Key('advisory_hr_bpm'),
                    controller: hrCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Heart rate (bpm)',
                    ),
                  ),
                  TextField(
                    key: const Key('advisory_hr_spo2'),
                    controller: spo2Ctrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'SpO₂ % (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('advisory_hr_review'),
                    onPressed: () {
                      final bpm = int.tryParse(hrCtrl.text.trim());
                      final spo2Raw = spo2Ctrl.text.trim();
                      final spo2 = spo2Raw.isEmpty ? null : int.tryParse(spo2Raw);
                      if (bpm == null) return;
                      final reading = AdvisoryHrReading(
                        heartRateBpm: bpm,
                        source: source,
                        spo2Percent: spo2,
                      );
                      if (!reading.isPlausibleHr || !reading.isPlausibleSpo2) {
                        return;
                      }
                      Navigator.of(ctx).pop(reading);
                    },
                    child: const Text('Review reading'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    hrCtrl.dispose();
    spo2Ctrl.dispose();
    if (draft == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm advisory reading'),
        content: Text(draft.confirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('advisory_hr_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _hr.setValue(draft.heartRateBpm);
      if (draft.spo2Percent != null) {
        _spo2.setValue(draft.spo2Percent!);
      }
      _advisoryApplied = draft;
    });
    _recomputeHrBand();
  }

  /// The first vital that still needs an answer (or has a wrong value), in screen order,
  /// with what a screen reader should say about it.
  (_VitalId, String)? _firstProblem() {
    String? problem(VitalInput input, VitalLimits limits,
            {bool decimal = false, bool optional = false}) =>
        vitalProblem(input, limits, decimal: decimal, optional: optional);
    String say(String name, bool missing, String? problem) => switch ((name, missing)) {
          ('Consciousness', true) => '$name missing. Choose a level or tap Not measured.',
          (_, true) => '$name missing. Enter a value or tap Not measured.',
          _ => '$name: $problem',
        };
    final checks = <(_VitalId, String, bool, String?)>[
      (
        _VitalId.bp,
        'Blood pressure',
        !(_sbp.answered && _dbp.answered),
        problem(_sbp, VitalLimits.systolicBp) ?? problem(_dbp, VitalLimits.diastolicBp),
      ),
      (_VitalId.hr, 'Heart rate', !_hr.answered, problem(_hr, VitalLimits.heartRate)),
      (_VitalId.rr, 'Breathing rate', !_rr.answered, problem(_rr, VitalLimits.respiratoryRate)),
      (
        _VitalId.temp,
        'Temperature',
        !_temp.answered,
        problem(_temp, VitalLimits.temperature, decimal: true),
      ),
      (
        _VitalId.spo2,
        'Oxygen saturation',
        false,
        problem(_spo2, VitalLimits.spo2, optional: true),
      ),
      (_VitalId.avpu, 'Consciousness', _avpu == null, _avpu == null ? 'missing' : null),
    ];
    for (final (id, name, missing, issue) in checks) {
      if (missing || issue != null) return (id, say(name, missing, issue));
    }
    return null;
  }

  void _pointAtFirstProblem() {
    final first = _firstProblem();
    if (first == null) return;
    final (id, message) = first;
    setState(() => _flagged = id);
    final card = _cardKeys[id]!.currentContext;
    if (card != null) {
      Scrollable.ensureVisible(
        card,
        alignment: 0.1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 250),
      );
    }
    SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr);
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) {
      _pointAtFirstProblem();
      return;
    }

    final consciousness = AvpuField.apiValue(_avpu);
    final vitals = <String, Object?>{
      'systolic_bp': _sbp.intValue,
      'diastolic_bp': _dbp.intValue,
      'heart_rate': _hr.intValue,
      'respiratory_rate': _rr.intValue,
      'temperature': _temp.doubleValue,
      'spo2': _spo2.intValue,
      'consciousness_level': consciousness,
    };
    if (widget.returnVitals) {
      Navigator.of(context).pop(vitals);
      return;
    }
    final moews = calculateMoews(
      sbp: _sbp.intValue,
      dbp: _dbp.intValue,
      hr: _hr.intValue,
      rr: _rr.intValue,
      temp: _temp.doubleValue,
      spo2: _spo2.intValue,
      consciousness: consciousness,
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

  /// Required vitals still unanswered: blood pressure (one item), heart rate, breathing
  /// rate, temperature and consciousness. Oxygen saturation is optional and never counted.
  int get _remaining => [
        _sbp.answered && _dbp.answered,
        _hr.answered,
        _rr.answered,
        _temp.answered,
        _avpu != null,
      ].where((answered) => !answered).length;

  void _changed() => setState(() => _flagged = null);

  @override
  Widget build(BuildContext context) {
    final hrAbnormal = _hrScore > 0;
    final text = Theme.of(context).textTheme;
    final remaining = _remaining;
    return Scaffold(
      // A visible back arrow; it does what Android back does.
      appBar: AppBar(leading: const BackButton(), title: const Text('Record vitals')),
      // Form.validate() would announce its first raw error ("Select AVPU or Not
      // measured"); "See result" announces the first missing vital by name instead.
      // The button bar is part of the body, not bottomNavigationBar, so it rides above the
      // keyboard instead of being hidden by it (round-6 device pass).
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(supportsAnnounce: false),
                child: Form(
                  key: _formKey,
                  // A plain scroll view (not a lazy list) so every card exists for "See result" to
                  // scroll to.
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                        YomaSpacing.gutter, YomaSpacing.sm, YomaSpacing.gutter, YomaSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BloodPressureField(
                          key: _cardKeys[_VitalId.bp],
                          systolic: _sbp,
                          diastolic: _dbp,
                          systolicKey: 'vitals_sbp',
                          diastolicKey: 'vitals_dbp',
                          flagged: _flagged == _VitalId.bp,
                          onChanged: _changed,
                        ),
                        VitalField(
                          key: _cardKeys[_VitalId.hr],
                          input: _hr,
                          limits: VitalLimits.heartRate,
                          label: 'Heart rate',
                          unit: 'bpm',
                          fieldKey: 'vitals_hr',
                          highlight: hrAbnormal,
                          flagged: _flagged == _VitalId.hr,
                          onChanged: _changed,
                          helperText: hrAbnormal
                              ? 'MOEWS HR band elevated (score $_hrScore) — may escalate referral'
                              : _advisoryApplied == null
                                  ? null
                                  : 'Applied ${_advisoryApplied!.source.label}: '
                                      '${_advisoryApplied!.heartRateBpm} bpm — confirm clinically.',
                          footer: TextButton(
                            key: const Key('advisory_hr_open'),
                            onPressed: _openAdvisoryHrSheet,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                              textStyle: text.labelSmall,
                            ),
                            child: const Text(
                              'From device ›',
                              semanticsLabel: 'Fill heart rate from a device (advisory)',
                            ),
                          ),
                        ),
                        VitalField(
                          key: _cardKeys[_VitalId.rr],
                          input: _rr,
                          limits: VitalLimits.respiratoryRate,
                          label: 'Breathing rate',
                          unit: '/min',
                          fieldKey: 'vitals_rr',
                          flagged: _flagged == _VitalId.rr,
                          onChanged: _changed,
                        ),
                        VitalField(
                          key: _cardKeys[_VitalId.temp],
                          input: _temp,
                          limits: VitalLimits.temperature,
                          label: 'Temperature',
                          unit: '°C',
                          fieldKey: 'vitals_temp',
                          decimal: true,
                          flagged: _flagged == _VitalId.temp,
                          onChanged: _changed,
                        ),
                        VitalField(
                          key: _cardKeys[_VitalId.spo2],
                          input: _spo2,
                          limits: VitalLimits.spo2,
                          label: 'Oxygen saturation',
                          unit: '%',
                          fieldKey: 'vitals_spo2',
                          optional: true,
                          flagged: _flagged == _VitalId.spo2,
                          onChanged: _changed,
                        ),
                        KeyedSubtree(
                          key: _cardKeys[_VitalId.avpu],
                          child: AvpuField(
                            key: const Key('vitals_avpu'),
                            idPrefix: 'vitals_avpu',
                            value: _avpu,
                            flagged: _flagged == _VitalId.avpu,
                            onChanged: (value) => setState(() {
                              _avpu = value;
                              _flagged = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: YomaColors.canvas,
              border: Border(top: BorderSide(color: YomaColors.grey200)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    YomaSpacing.gutter, YomaSpacing.sm, YomaSpacing.gutter, YomaSpacing.sm),
                child: FilledButton(
                  key: const Key('vitals_see_result'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(YomaSizes.primaryButton),
                  ),
                  // Always enabled: a tap with gaps scrolls to the first missing vital and says so.
                  onPressed: _continue,
                  child: Text(
                    widget.returnVitals
                        ? (remaining == 0 ? 'Save vitals' : 'Save vitals – $remaining left')
                        : (remaining == 0 ? 'See result' : 'See result – $remaining left'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The vitals in screen order.
enum _VitalId { bp, hr, rr, temp, spo2, avpu }
