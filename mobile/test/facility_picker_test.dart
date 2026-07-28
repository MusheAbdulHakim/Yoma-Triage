import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/models/facility_catalog.dart';
import 'package:yoma_triage/screens/facility_picker_screen.dart';
import 'package:yoma_triage/services/geo.dart';

void main() {
  testWidgets('picker returns selected facility on tap', (tester) async {
    final ranked = rankNearest(
      originLat: 9.403,
      originLon: -0.842,
      facilities: const [
        CatalogFacility(
          id: 1,
          name: 'Tamale Teaching Hospital',
          latitude: 9.404,
          longitude: -0.843,
          district: 'Tamale Metropolitan',
          hasMaternity: true,
          hasIcu: true,
          type: 'teaching_hospital',
        ),
        CatalogFacility(
          id: 3,
          name: 'Savelugu Municipal Hospital',
          latitude: 9.6245,
          longitude: -0.8251,
          district: 'Savelugu Municipal',
          hasMaternity: true,
          hasIcu: false,
          type: 'municipal_hospital',
        ),
      ],
    );

    CatalogFacility? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<CatalogFacility>(
                  MaterialPageRoute(
                    builder: (_) => FacilityPickerScreen(ranked: ranked),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Using Home CHPS location'), findsOneWidget);
    await tester.tap(find.text('Savelugu Municipal Hospital'));
    await tester.pumpAndSettle();
    expect(picked?.id, 3);
  });
}
