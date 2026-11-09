import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cho_store.dart';
import '../services/contacts_store.dart';
import '../services/friendly_time.dart';
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

  String _updatedText(DateTime updatedAt) =>
      'Contacts last updated: ${friendlyWhen(context, updatedAt)}';

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

  /// One contact as in the design: the name (and role) on the left, Call and SMS on the
  /// right. On a narrow screen or with large text the buttons go under the name.
  Widget _contact({
    required String title,
    required String subtitle,
    required String phone,
    required String message,
  }) {
    final text = Theme.of(context).textTheme;
    final call = Semantics(
      button: true,
      label: 'Call $title',
      excludeSemantics: true,
      child: FilledButton(
        key: Key('call_$phone'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, YomaSizes.minTap),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: text.labelMedium,
        ),
        onPressed: () => _open(Uri(scheme: 'tel', path: phone), phone),
        child: const Text('Call'),
      ),
    );
    final sms = Semantics(
      button: true,
      label: 'SMS $title',
      excludeSemantics: true,
      child: OutlinedButton(
        key: Key('sms_$phone'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, YomaSizes.minTap),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          side: const BorderSide(color: YomaColors.border, width: 1),
          foregroundColor: YomaColors.grey900,
        ),
        onPressed: () => _open(
          // Encoded by hand: queryParameters would turn spaces into "+".
          Uri.parse('sms:$phone?body=${Uri.encodeComponent(message)}'),
          phone,
        ),
        child: const Text('SMS'),
      ),
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        Text(subtitle, style: text.bodySmall?.copyWith(color: YomaColors.grey600)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: YomaSpacing.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: BoxDecoration(
          color: YomaColors.surface,
          borderRadius: BorderRadius.circular(YomaRadii.md),
          border: Border.all(color: YomaColors.grey200),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final oneRow = constraints.maxWidth >= 280 &&
                MediaQuery.textScalerOf(context).scale(16) <= 16 * 1.15;
            if (oneRow) {
              return Row(
                children: [
                  Expanded(child: name),
                  call,
                  const SizedBox(width: 8),
                  sms,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: call),
                    const SizedBox(width: 8),
                    Expanded(child: sms),
                  ],
                ),
              ],
            );
          },
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
        final facilities =
            contacts.facilities.where((facility) => widget.facilityIds.contains(facility.id));
        return Column(
          key: const Key('manual_contacts'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _updatedText(contacts.updatedAt),
              key: const Key('contacts_updated'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: YomaColors.grey700),
            ),
            for (final driver in contacts.drivers)
              _contact(
                title: driver.name,
                subtitle: driver.isMotorKing ? 'Motor-King' : 'Other vehicle',
                phone: driver.phone,
                message: driverMessage(compoundName),
              ),
            if (contacts.drivers.isEmpty) const Text('No drivers are saved for this compound.'),
            for (final facility in facilities)
              _contact(
                title: facility.name,
                subtitle: 'Receiving facility',
                phone: facility.phone,
                message: facilityMessage(compoundName),
              ),
          ],
        );
      },
    );
  }
}
