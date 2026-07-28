/// Advisory BLE / contact-PPG heart-rate fill-in (Phase E2).
///
/// Does not pair hardware yet — CHO enters or confirms a device reading.
/// Always optional and non-blocking; manual vitals remain authoritative.
library;

enum AdvisoryHrSource {
  blePulseOx,
  contactPpg,
  otherDevice,
}

extension AdvisoryHrSourceLabel on AdvisoryHrSource {
  String get label => switch (this) {
        AdvisoryHrSource.blePulseOx => 'BLE pulse ox',
        AdvisoryHrSource.contactPpg => 'Contact PPG',
        AdvisoryHrSource.otherDevice => 'Other device',
      };
}

class AdvisoryHrReading {
  const AdvisoryHrReading({
    required this.heartRateBpm,
    required this.source,
    this.spo2Percent,
  });

  final int heartRateBpm;
  final AdvisoryHrSource source;
  final int? spo2Percent;

  bool get isPlausibleHr => heartRateBpm >= 30 && heartRateBpm <= 250;

  bool get isPlausibleSpo2 =>
      spo2Percent == null || (spo2Percent! >= 50 && spo2Percent! <= 100);

  String get confirmMessage =>
      'Apply advisory ${source.label} reading of $heartRateBpm bpm'
      '${spo2Percent != null ? ' / SpO₂ $spo2Percent%' : ''}? '
      'Confirm against your clinical check — device readings can be wrong.';
}
