/// The emergency types the app offers: the API value and what the CHO reads. The API
/// values are fixed (the server accepts exactly these); only the wording is shown.
/// `tests/test_referral_validation.py` checks every value here is accepted by the API.
const emergencyTypes = <(String, String)>[
  ('pph', 'Heavy bleeding'),
  ('eclampsia', 'Fits (eclampsia)'),
  ('respiratory_distress', 'Breathing problem'),
  ('neonatal_asphyxia', 'Newborn not breathing'),
];

/// The words for an emergency type's API value; never the raw code.
String emergencyTypeLabel(String? code) {
  for (final (value, label) in emergencyTypes) {
    if (value == code) return label;
  }
  return 'Emergency';
}
