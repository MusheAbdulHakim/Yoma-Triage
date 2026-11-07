import 'dart:convert';

import 'package:yoma_triage/services/cho_store.dart';

const testChoPhone = '+233240000100';

/// SharedPreferences values for a phone that has finished setup.
Map<String, Object> registeredChoPrefs({
  int compoundId = 1,
  String compoundName = 'Tamale South CHPS',
  String phone = testChoPhone,
}) =>
    {
      ChoStore.prefsKey: jsonEncode(
        ChoIdentity(
          phone: phone,
          name: 'Abiba',
          compoundId: compoundId,
          compoundName: compoundName,
        ).toJson(),
      ),
    };
