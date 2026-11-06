class ReferralRequest {
  final String clientRequestId;
  final int chpsCompoundId;
  final int facilityId;
  final String patientHash;

  /// In-memory display label only — never serialized to outbox/API JSON.
  final String? patientName;
  final String emergencyType;
  final Map<String, dynamic> vitals;
  final String? aiScreenResult;
  final double? aiConfidence;
  final String? aiModelVersion;
  final String? catalogVersion;
  final double? originLat;
  final double? originLon;
  final String? originSource;

  /// "Emergency: skip vitals": dispatch at once with no clinical assessment.
  final bool vitalsNotTaken;

  ReferralRequest({
    required this.clientRequestId,
    required this.chpsCompoundId,
    required this.facilityId,
    required this.patientHash,
    this.patientName,
    required this.emergencyType,
    required this.vitals,
    this.aiScreenResult,
    this.aiConfidence,
    this.aiModelVersion,
    this.catalogVersion,
    this.originLat,
    this.originLon,
    this.originSource,
    this.vitalsNotTaken = false,
  });

  Map<String, dynamic> toJson() => {
        'client_request_id': clientRequestId,
        'chps_compound_id': chpsCompoundId,
        'facility_id': facilityId,
        'patient_hash': patientHash,
        'emergency_type': emergencyType,
        'vitals': vitals,
        if (vitalsNotTaken) 'vitals_not_taken': true,
        if (aiScreenResult != null) 'ai_screen_result': aiScreenResult,
        if (aiConfidence != null) 'ai_confidence': aiConfidence,
        if (aiModelVersion != null) 'ai_model_version': aiModelVersion,
        if (catalogVersion != null) 'catalog_version': catalogVersion,
        if (originLat != null) 'origin_lat': originLat,
        if (originLon != null) 'origin_lon': originLon,
        if (originSource != null) 'origin_source': originSource,
      };
}
