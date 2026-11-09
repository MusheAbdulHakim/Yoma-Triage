import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/theme/yoma_theme.dart';

/// Colour-vision deficiency simulation (Machado, Oliveira & Fernandes 2009, severity 1.0),
/// applied in linear RGB.
const _simulations = {
  'protanopia': [
    [0.152286, 1.052583, -0.204868],
    [0.114503, 0.786281, 0.099216],
    [-0.003882, -0.048116, 1.051998],
  ],
  'deuteranopia': [
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
  ],
  'tritanopia': [
    [1.255528, -0.076749, -0.178779],
    [-0.078411, 0.930809, 0.147602],
    [0.004733, 0.691367, 0.303900],
  ],
};

double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

List<double> _linear(Color c) => [_lin(c.r), _lin(c.g), _lin(c.b)];

double _luminance(List<double> l) => 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2];

List<double> _simulate(Color c, List<List<double>> m) {
  final l = _linear(c);
  return [
    for (final row in m)
      (row[0] * l[0] + row[1] * l[1] + row[2] * l[2]).clamp(0.0, 1.0),
  ];
}

double _contrast(double a, double b) {
  final (lo, hi) = a < b ? (a, b) : (b, a);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('Elevated card text (navy on amber) meets WCAG AA', () {
    final ratio = _contrast(_luminance(_linear(TriageColors.onAmber)),
        _luminance(_linear(TriageColors.amberFill)));
    expect(ratio, greaterThanOrEqualTo(4.5));
  });

  test('Elevated stays clearly lighter than Critical with normal vision', () {
    final ratio = _contrast(
        _luminance(_linear(TriageColors.red)), _luminance(_linear(TriageColors.amberFill)));
    expect(ratio, greaterThanOrEqualTo(2.0));
  });

  for (final MapEntry(key: name, value: m) in _simulations.entries) {
    test('$name: Elevated and Critical cards still differ, and the text stays readable', () {
      final red = _luminance(_simulate(TriageColors.red, m));
      final amber = _luminance(_simulate(TriageColors.amberFill, m));
      final text = _luminance(_simulate(TriageColors.onAmber, m));
      // A clear lightness difference, not only a hue one (the cards also differ in
      // text colour, icon and word).
      expect(_contrast(red, amber), greaterThanOrEqualTo(2.0), reason: name);
      expect(_contrast(text, amber), greaterThanOrEqualTo(4.5), reason: name);
    });
  }
}
