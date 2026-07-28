import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/services/catalog_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('bootstrap catalog loads 16 Northern MMDAs with coords', () async {
    final graph = await CatalogStore().load();
    expect(graph.version, '2026-07-28.3');
    expect(graph.compounds.length, 16);
    expect(graph.facilities.length, 16);
    final withCoords = graph.facilities
        .where((f) => f.latitude != null && f.longitude != null);
    expect(withCoords.length, 16);
  });

  test('home CHPS default is 1', () async {
    final id = await CatalogStore().homeChpsCompoundId();
    expect(id, 1);
  });

  test('catalog is stale until first sync', () async {
    expect(await CatalogStore().isStale(), isTrue);
  });

  test('catalog not stale when synced recently', () async {
    SharedPreferences.setMockInitialValues({
      CatalogConfig.syncedAtPrefsKey: DateTime.now().toUtc().toIso8601String(),
      CatalogConfig.catalogVersionPrefsKey: '2026-07-28.2',
    });
    expect(await CatalogStore().isStale(), isFalse);
  });

  test('catalog stale when synced over 30 days ago', () async {
    final old = DateTime.now().toUtc().subtract(const Duration(days: 31));
    SharedPreferences.setMockInitialValues({
      CatalogConfig.syncedAtPrefsKey: old.toIso8601String(),
    });
    expect(await CatalogStore().isStale(), isTrue);
  });
}
