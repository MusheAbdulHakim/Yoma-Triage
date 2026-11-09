import '../parameters.dart';

/// Allowed range for a typed vital. The API rejects anything outside these with a
/// 422, and a rejected referral would otherwise sit in the outbox retrying forever.
///
/// These catch typos and impossible readings; they are not clinical thresholds.
class VitalLimits {
  const VitalLimits(this.min, this.max);

  static const systolicBp = VitalLimits(
    Parameters.systolicBpMin,
    Parameters.systolicBpMax,
  );
  static const diastolicBp = VitalLimits(
    Parameters.diastolicBpMin,
    Parameters.diastolicBpMax,
  );
  static const heartRate = VitalLimits(
    Parameters.heartRateMin,
    Parameters.heartRateMax,
  );
  static const respiratoryRate = VitalLimits(
    Parameters.respiratoryRateMin,
    Parameters.respiratoryRateMax,
  );
  static const temperature = VitalLimits(
    Parameters.temperatureMin,
    Parameters.temperatureMax,
  );
  static const spo2 = VitalLimits(
    Parameters.spo2Min,
    Parameters.spo2Max,
  );

  final num min;
  final num max;

  String? errorFor(num value) =>
      value < min || value > max ? 'Check this value: must be $min to $max' : null;
}
