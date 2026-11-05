/// Allowed range for a typed vital. Keep in sync with `src/api/referral.py`: the
/// API rejects anything outside these with a 422, and a rejected referral would
/// otherwise sit in the outbox retrying forever.
///
/// These catch typos and impossible readings; they are not clinical thresholds.
class VitalLimits {
  const VitalLimits(this.min, this.max);

  static const systolicBp = VitalLimits(0, 300);
  static const diastolicBp = VitalLimits(0, 200);
  static const heartRate = VitalLimits(0, 300);
  static const respiratoryRate = VitalLimits(0, 120);
  static const temperature = VitalLimits(20, 45);
  static const spo2 = VitalLimits(0, 100);

  final num min;
  final num max;

  String? errorFor(num value) => value < min || value > max
      ? 'Check this value: must be $min to $max'
      : null;
}
