import '../generated/clinical_parameters.dart';

/// Allowed range for a typed vital. The API rejects anything outside these with a
/// 422, and a rejected referral would otherwise sit in the outbox retrying forever.
///
/// These catch typos and impossible readings; they are not clinical thresholds.
class VitalLimits {
  const VitalLimits(this.min, this.max);

  static const systolicBp = VitalLimits(
    ClinicalParameters.systolicBpMin,
    ClinicalParameters.systolicBpMax,
  );
  static const diastolicBp = VitalLimits(
    ClinicalParameters.diastolicBpMin,
    ClinicalParameters.diastolicBpMax,
  );
  static const heartRate = VitalLimits(
    ClinicalParameters.heartRateMin,
    ClinicalParameters.heartRateMax,
  );
  static const respiratoryRate = VitalLimits(
    ClinicalParameters.respiratoryRateMin,
    ClinicalParameters.respiratoryRateMax,
  );
  static const temperature = VitalLimits(
    ClinicalParameters.temperatureMin,
    ClinicalParameters.temperatureMax,
  );
  static const spo2 = VitalLimits(
    ClinicalParameters.spo2Min,
    ClinicalParameters.spo2Max,
  );

  final num min;
  final num max;

  String? errorFor(num value) => value < min || value > max
      ? 'Check this value: must be $min to $max'
      : null;
}
