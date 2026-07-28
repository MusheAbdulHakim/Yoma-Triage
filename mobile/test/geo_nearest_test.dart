import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/models/facility_catalog.dart';
import 'package:yoma_triage/services/geo.dart';

void main() {
  test('Tamale CHPS ranks TTH ahead of far hospital', () {
    final ranked = rankNearest(
      originLat: 9.403,
      originLon: -0.842,
      facilities: [
        const CatalogFacility(
          id: 1,
          name: 'TTH',
          latitude: 9.404,
          longitude: -0.843,
          district: 'Tamale Metropolitan',
          hasMaternity: true,
          hasIcu: true,
          type: 'teaching_hospital',
        ),
        const CatalogFacility(
          id: 99,
          name: 'Far',
          latitude: 10.9,
          longitude: -1.0,
          district: 'Far District',
          hasMaternity: true,
          hasIcu: false,
          type: 'district_hospital',
        ),
      ],
    );
    expect(ranked.first.id, 1);
    expect(ranked.first.distanceKm, lessThan(5));
  });

  test('maternityOnly filters non-maternity sites', () {
    final ranked = rankNearest(
      originLat: 9.4,
      originLon: -0.84,
      maternityOnly: true,
      facilities: [
        const CatalogFacility(
          id: 2,
          name: 'No maternity',
          latitude: 9.401,
          longitude: -0.841,
          district: 'Tamale Metropolitan',
          hasMaternity: false,
          hasIcu: false,
          type: 'clinic',
        ),
        const CatalogFacility(
          id: 1,
          name: 'Maternity',
          latitude: 9.41,
          longitude: -0.85,
          district: 'Tamale Metropolitan',
          hasMaternity: true,
          hasIcu: false,
          type: 'district_hospital',
        ),
      ],
    );
    expect(ranked.map((r) => r.id), [1]);
  });
}
