import 'dart:math';

import '../models/facility_catalog.dart';

class RankedFacility {
  final CatalogFacility facility;
  final double distanceKm;

  const RankedFacility({
    required this.facility,
    required this.distanceKm,
  });

  int get id => facility.id;
  String get name => facility.name;
}

double haversineKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRad(double deg) => deg * pi / 180.0;

List<RankedFacility> rankNearest({
  required double originLat,
  required double originLon,
  required List<CatalogFacility> facilities,
  bool maternityOnly = true,
}) {
  final filtered = facilities.where((f) {
    if (f.latitude == null || f.longitude == null) return false;
    if (maternityOnly && !f.hasMaternity) return false;
    return true;
  });

  final ranked = filtered
      .map(
        (f) => RankedFacility(
          facility: f,
          distanceKm: haversineKm(
            originLat,
            originLon,
            f.latitude!,
            f.longitude!,
          ),
        ),
      )
      .toList()
    ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

  return ranked;
}
