import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/audio_recorder_base.dart';
import 'package:yoma_triage/widgets/breathing_check.dart';

/// Sizes from the pulse frames (224 dp box): the innermost ring at 84 dp, the edge at 111.
const _inner = 84.0;
const _outer = 111.0;

double _widest(double level) {
  var widest = 0.0;
  for (var p = 0.0; p < 1; p += 0.01) {
    for (final r in pulseRings(level: level, phase: p, inner: _inner, outer: _outer)) {
      if (r.radius > widest) widest = r.radius;
    }
  }
  return widest;
}

void main() {
  test('breathing near the phone sends the rings to the edge, as in pulse frame 3', () {
    // About -30 dBFS: breathing close to a phone microphone.
    final level = levelFromDbfs(-30);
    expect(level, greaterThan(0.6));
    expect(_widest(level), greaterThan(_outer * 0.97));
  });

  test('silence keeps the rings close to the circle, as in pulse frame 1', () {
    expect(_widest(levelFromDbfs(-60)), lessThan(_inner + (_outer - _inner) * 0.31));
  });

  test('every ring stays visible: the faintest is at least 15% opacity', () {
    for (var p = 0.0; p < 1; p += 0.05) {
      for (final r in pulseRings(level: 1, phase: p, inner: _inner, outer: _outer)) {
        expect(r.alpha, greaterThanOrEqualTo(0.15));
      }
    }
  });

  testWidgets('a live level stream moves the rings (fake microphone)', (tester) async {
    final level = ValueNotifier<double>(0);
    final mic = StreamController<double>();
    addTearDown(mic.close);
    // Smoothed the way the recording screen does it.
    mic.stream.listen((v) => level.value = level.value * 0.5 + v * 0.5);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: RecordingPulse(remaining: 12, total: 15, level: level)),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      mic.add(levelFromDbfs(-28));
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(level.value, greaterThan(0.7));
    expect(tester.takeException(), isNull);
  });
}
