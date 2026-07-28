import 'package:flutter/material.dart';

import '../services/geo.dart';
import '../theme/yoma_theme.dart';

/// Manual nearest-facility picker. Top 3 suggested; override mandatory.
class FacilityPickerScreen extends StatelessWidget {
  final List<RankedFacility> ranked;
  final int? selectedFacilityId;
  final String originBanner;

  const FacilityPickerScreen({
    super.key,
    required this.ranked,
    this.selectedFacilityId,
    this.originBanner = 'Using Home CHPS location',
  });

  @override
  Widget build(BuildContext context) {
    final top = ranked.take(3).toList();
    final rest =
        ranked.length > 3 ? ranked.skip(3).toList() : const <RankedFacility>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Choose receiving facility')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: YomaColors.caution.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                originBanner,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Nearest (top 3)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          ...top.map((r) => _tile(context, r, highlight: true)),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'All facilities',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            ...rest.map((r) => _tile(context, r, highlight: false)),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, RankedFacility r,
      {required bool highlight}) {
    final selected = r.id == selectedFacilityId;
    return Card(
      color: selected
          ? YomaColors.brand.withValues(alpha: 0.12)
          : (highlight ? Colors.white : null),
      child: ListTile(
        title: Text(r.name),
        subtitle: Text(
          '${r.facility.district} · ${r.distanceKm.toStringAsFixed(1)} km'
          '${r.facility.hasMaternity ? ' · maternity' : ''}',
        ),
        trailing: selected ? const Icon(Icons.check_circle) : null,
        onTap: () => Navigator.of(context).pop(r.facility),
      ),
    );
  }
}
