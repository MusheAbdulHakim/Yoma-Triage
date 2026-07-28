bool referralIndicated({
  required String acousticLabel,
  String? moewsRiskLevel,
  bool emergencyBypass = false,
  bool choReferDespiteInconclusive = false,
}) {
  if (emergencyBypass) return true;
  final moews = (moewsRiskLevel ?? 'UNKNOWN').toUpperCase();
  // Escalate-only: MOEWS RED never suppressed by acoustic GREEN.
  if (moews == 'RED') return true;
  if (acousticLabel.toUpperCase() == 'RED') return true;
  if (acousticLabel.toUpperCase() == 'INCONCLUSIVE' &&
      choReferDespiteInconclusive) {
    return true;
  }
  // YELLOW: CTA may offer refer; treat as indicated for primary Confirm
  // when MOEWS attention exists (spec §6.1).
  if (moews == 'YELLOW') return true;
  return false;
}
