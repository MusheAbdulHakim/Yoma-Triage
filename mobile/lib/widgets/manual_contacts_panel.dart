import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cho_store.dart';
import '../services/contacts_store.dart';
import '../theme/yoma_theme.dart';

typedef ContactLauncher = Future<bool> Function(Uri uri);

Future<bool> launchWithPhone(Uri uri) => launchUrl(uri);

/// Principle 9: when the system can't help, the CHO can still reach people. This reads
/// only what is saved on the phone and makes no network call, so it works offline.
class ManualContactsPanel extends StatefulWidget {
  const ManualContactsPanel({
    super.key,
    this.facilityIds = const {},
    this.launcher = launchWithPhone,
    this.onContactUsed,
  });

  /// The facilities chosen for these referrals.
  final Set<int> facilityIds;
  final ContactLauncher launcher;

  /// Called when the CHO taps Call or SMS.
  final VoidCallback? onContactUsed;

  @override
  State<ManualContactsPanel> createState() => _ManualContactsPanelState();
}

class _ManualContactsPanelState extends State<ManualContactsPanel> {
  late final Future<(CachedContacts?, ChoIdentity?)> _saved = _load();

  Future<(CachedContacts?, ChoIdentity?)> _load() async =>
      (await ContactsStore().load(), await ChoStore().load());

  /// Never names the patient: an SMS can be read by anyone holding the phone.
  static String driverMessage(String compoundName) =>
      'Yoma Triage: Emergency transport needed at $compoundName. Please call back now.';

  static String facilityMessage(String compoundName) =>
      'Yoma Triage: Emergency referral coming from $compoundName. '
      'Please prepare and call back.';

  static String _updatedText(DateTime updatedAt) {
    final local = updatedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Contacts last updated: ${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _open(Uri uri, String phone) async {
    widget.onContactUsed?.call();
    var opened = false;
    try {
      opened = await widget.launcher(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the phone app. Dial $phone by hand.')),
      );
    }
  }

  Widget _contact({
    required String title,
    required String subtitle,
    required String phone,
    required String message,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('$subtitle · $phone'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: Key('call_$phone'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _open(Uri(scheme: 'tel', path: phone), phone),
                    icon: const Icon(Icons.call),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('sms_$phone'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _open(
                      // Encoded by hand: queryParameters would turn spaces into "+".
                      Uri.parse('sms:$phone?body=${Uri.encodeComponent(message)}'),
                      phone,
                    ),
                    icon: const Icon(Icons.sms),
                    label: const Text('SMS'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(CachedContacts?, ChoIdentity?)>(
      future: _saved,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final (contacts, identity) = snapshot.data ?? (null, null);
        final compoundName = identity?.compoundName ?? 'your CHPS compound';
        if (contacts == null) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'No contacts saved on this phone yet. Use your own contact list.',
                key: Key('contacts_none_saved'),
              ),
            ),
          );
        }
        final facilities = contacts.facilities
            .where((facility) => widget.facilityIds.contains(facility.id));
        return Column(
          key: const Key('manual_contacts'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Reach them yourself',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: YomaColors.brand,
              ),
            ),
            Text(
              _updatedText(contacts.updatedAt),
              key: const Key('contacts_updated'),
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            for (final facility in facilities)
              _contact(
                title: facility.name,
                subtitle: 'Receiving facility',
                phone: facility.phone,
                message: facilityMessage(compoundName),
              ),
            for (final driver in contacts.drivers)
              _contact(
                title: driver.name,
                subtitle: driver.isMotorKing ? 'Motor-King' : 'Other vehicle',
                phone: driver.phone,
                message: driverMessage(compoundName),
              ),
            if (contacts.drivers.isEmpty)
              const Text('No drivers are saved for this compound.'),
          ],
        );
      },
    );
  }
}
