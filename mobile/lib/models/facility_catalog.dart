class CatalogCompound {
  final int id;
  final String name;
  final double? latitude;
  final double? longitude;
  final String district;

  const CatalogCompound({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.district,
  });

  factory CatalogCompound.fromJson(Map<String, dynamic> json) {
    return CatalogCompound(
      id: json['id'] as int,
      name: json['name'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      district: json['district'] as String? ?? '',
    );
  }
}

class CatalogFacility {
  final int id;
  final String name;
  final double? latitude;
  final double? longitude;
  final String district;
  final bool hasMaternity;
  final bool hasIcu;
  final String type;

  const CatalogFacility({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.district,
    required this.hasMaternity,
    required this.hasIcu,
    required this.type,
  });

  /// Convenience aliases used by geo ranking.
  double? get lat => latitude;
  double? get lon => longitude;

  factory CatalogFacility.fromJson(Map<String, dynamic> json) {
    return CatalogFacility(
      id: json['id'] as int,
      name: json['name'] as String,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      district: json['district'] as String? ?? '',
      hasMaternity: json['has_maternity'] as bool? ?? false,
      hasIcu: json['has_icu'] as bool? ?? false,
      type: json['type'] as String? ?? 'district_hospital',
    );
  }
}

class PreferredLink {
  final int chpsCompoundId;
  final int facilityId;

  const PreferredLink({
    required this.chpsCompoundId,
    required this.facilityId,
  });

  factory PreferredLink.fromJson(Map<String, dynamic> json) {
    return PreferredLink(
      chpsCompoundId: json['chps_compound_id'] as int,
      facilityId: json['facility_id'] as int,
    );
  }
}

class ReferralGraph {
  final String version;
  final String region;
  final List<CatalogCompound> compounds;
  final List<CatalogFacility> facilities;
  final List<PreferredLink> preferredLinks;

  const ReferralGraph({
    required this.version,
    required this.region,
    required this.compounds,
    required this.facilities,
    required this.preferredLinks,
  });

  factory ReferralGraph.fromJson(Map<String, dynamic> json) {
    final compoundsRaw = json['compounds'] as List<dynamic>? ?? const [];
    final facilitiesRaw = json['facilities'] as List<dynamic>? ?? const [];
    final linksRaw = json['preferred_links'] as List<dynamic>? ?? const [];
    return ReferralGraph(
      version: json['version'] as String? ?? '',
      region: json['region'] as String? ?? 'northern',
      compounds: compoundsRaw
          .map((e) => CatalogCompound.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      facilities: facilitiesRaw
          .map((e) => CatalogFacility.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      preferredLinks: linksRaw
          .map((e) => PreferredLink.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  CatalogCompound? compoundById(int id) {
    for (final c in compounds) {
      if (c.id == id) return c;
    }
    return null;
  }

  CatalogFacility? facilityById(int id) {
    for (final f in facilities) {
      if (f.id == id) return f;
    }
    return null;
  }
}
