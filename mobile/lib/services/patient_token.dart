import 'dart:math';

import 'package:crypto/crypto.dart';

/// Cryptographically random unlinkable patient token (SHA-256 hex).
///
/// Never derive from patient name or other identifiable data.
String patientToken() {
  final random = Random.secure();
  final material = List<int>.generate(32, (_) => random.nextInt(256));
  return sha256.convert(material).toString();
}
