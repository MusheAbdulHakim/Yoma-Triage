import '../parameters.dart';
import 'moews_calculator.dart';

/// One line of the Result screen's "Why" list.
class WhyRow {
  const WhyRow({required this.text, required this.critical});

  /// e.g. "Systolic BP 185 mmHg – very high".
  final String text;

  /// A parameter scoring the red-level value (3) rather than borderline (1).
  final bool critical;
}

/// Display names for the vitals, matching the Record vitals screen.
const vitalDisplayNames = {
  'systolic_bp': 'Systolic BP',
  'diastolic_bp': 'Diastolic BP',
  'heart_rate': 'Heart rate',
  'respiratory_rate': 'Breathing rate',
  'temperature': 'Temperature',
  'spo2': 'Oxygen saturation',
  'consciousness_level': 'Consciousness',
};

const _units = {
  'systolic_bp': 'mmHg',
  'diastolic_bp': 'mmHg',
  'heart_rate': 'bpm',
  'respiratory_rate': 'per min',
  'temperature': '°C',
  'spo2': '%',
};

const _avpuWords = {'A': 'Alert', 'V': 'Voice', 'P': 'Pain', 'U': 'Unresponsive'};

/// Explains a MOEWS result from the app's own scores: which measured parameters
/// contributed, critical ones first. Presentation only; it never changes a score.
///
/// Critical parameters read "very high" / "very low"; borderline ones "high" / "low".
List<WhyRow> explainMoews(MoewsResult moews, Map<String, Object?> vitals) {
  final rows = <WhyRow>[];

  void band(String key, int score, MoewsBand band) {
    if (score == 0) return;
    final value = vitals[key];
    if (value is! num) return;
    final critical = score >= Parameters.moewsRedParameterScore;
    final low = critical
        ? (band.redBelow != null && value < band.redBelow!)
        : (band.yellowLowMin != null &&
            band.yellowLowMax != null &&
            value >= band.yellowLowMin! &&
            value <= band.yellowLowMax!);
    final direction = critical ? (low ? 'very low' : 'very high') : (low ? 'low' : 'high');
    rows.add(WhyRow(
      text: '${vitalDisplayNames[key]} ${_format(value)} ${_units[key]} – $direction',
      critical: critical,
    ));
  }

  band('systolic_bp', moews.sbpScore, Parameters.systolicBpBand);
  band('diastolic_bp', moews.dbpScore, Parameters.diastolicBpBand);
  band('heart_rate', moews.hrScore, Parameters.heartRateBand);
  band('respiratory_rate', moews.rrScore, Parameters.respiratoryRateBand);
  band('temperature', moews.tempScore, Parameters.temperatureBand);
  band('spo2', moews.spo2Score, Parameters.spo2Band);

  final avpu = vitals['consciousness_level'];
  if (moews.consciousnessScore > 0 && avpu is String) {
    rows.add(WhyRow(
      text: 'Consciousness: ${_avpuWords[avpu.toUpperCase()] ?? avpu} – not alert',
      critical: moews.consciousnessScore >= Parameters.moewsRedParameterScore,
    ));
  }

  // Critical first; otherwise keep the form's order.
  final critical = rows.where((r) => r.critical);
  final borderline = rows.where((r) => !r.critical);
  return [...critical, ...borderline];
}

/// Names for the "Not measured" list: systolic and diastolic missing together read as one
/// "Blood pressure" row, as in the design.
List<String> missingDisplayNames(List<String> missing) {
  final bothBp = missing.contains('systolic_bp') && missing.contains('diastolic_bp');
  return [
    for (final key in missing)
      if (bothBp && key == 'systolic_bp')
        'Blood pressure'
      else if (!(bothBp && key == 'diastolic_bp'))
        vitalDisplayNames[key] ?? key,
  ];
}

/// For a result with nothing abnormal: the main measured vitals, "– normal", as in the design.
List<String> normalRows(Map<String, Object?> vitals) {
  final rows = <String>[];
  for (final key in ['systolic_bp', 'heart_rate', 'respiratory_rate', 'temperature']) {
    final value = vitals[key];
    if (value is num) rows.add('${vitalDisplayNames[key]} ${_format(value)} ${_units[key]} – normal');
  }
  return rows;
}

String _format(num value) =>
    value is double && value != value.roundToDouble() ? value.toString() : value.round().toString();
