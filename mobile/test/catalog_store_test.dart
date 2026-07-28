import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/services/catalog_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bootstrap catalog loads version and facilities with coords', () async {
    final graph = await CatalogStore().load();
    expect(graph.version, isNotEmpty);
    expect(graph.facilities, isNotEmpty);
    final withCoords = graph.facilities
        .where((f) => f.latitude != null && f.longitude != null);
    expect(withCoords.length, greaterThanOrEqualTo(1));
  });

  test('home CHPS default is 1', () async {
    final id = await CatalogStore().homeChpsCompoundId();
    expect(id, 1);
  });
}
