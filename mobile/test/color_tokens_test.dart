// Every colour comes from the design-system tokens in lib/theme/yoma_theme.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no hex colour outside the theme module', () {
    for (final file in files) {
      if (file.path.endsWith('theme/yoma_theme.dart')) continue;
      final hits = RegExp(r'Color\(0x').allMatches(file.readAsStringSync()).length;
      expect(hits, 0, reason: file.path);
    }
  });

  test('no Material colour names outside the theme module (transparent is fine)', () {
    final named = RegExp(r'(?<![A-Za-z])Colors\.(?!transparent\b)[a-z]\w*');
    for (final file in files) {
      if (file.path.endsWith('theme/yoma_theme.dart')) continue;
      final hits = named.allMatches(file.readAsStringSync()).map((m) => m[0]).toList();
      expect(hits, isEmpty, reason: file.path);
    }
  });

  test('the old teal is gone', () {
    for (final file in files) {
      expect(file.readAsStringSync().toUpperCase().contains('005F60'), isFalse,
          reason: file.path);
    }
  });
}
