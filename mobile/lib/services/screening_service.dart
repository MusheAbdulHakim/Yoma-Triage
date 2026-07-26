import 'package:flutter/foundation.dart' show kIsWeb;

import 'audio_recorder.dart';
import 'screening_result.dart';
import 'yamnet_classifier.dart';

/// Facade: web simulator vs Android record + YAMNet (stub fallback).
class ScreeningService {
  ScreeningService({
    YamnetClassifier? classifier,
    AudioRecorderService? recorder,
  })  : _classifier = classifier,
        _recorder = recorder;

  YamnetClassifier? _classifier;
  AudioRecorderService? _recorder;

  bool get isWebSimulator => kIsWeb;

  Future<void> startRecording() async {
    if (kIsWeb) return;
    _recorder ??= createAudioRecorder();
    await _recorder!.start();
  }

  Future<ScreeningResult> stopAndClassify({bool forceRed = false}) async {
    if (kIsWeb) {
      return simulatorClassify(forceRed: forceRed);
    }

    try {
      final pcm = await (_recorder ?? createAudioRecorder()).stop();
      _classifier ??= await createYamnetClassifier(forceRed: forceRed);
      return _classifier!.classifyPcm16kHzMono(pcm);
    } catch (e) {
      if (e.toString().contains('permission')) {
        return ScreeningResult(
          label: 'INCONCLUSIVE',
          confidence: 0.0,
          reason: 'Mic permission denied — use Emergency Referral bypass',
          source: 'stub',
        );
      }
      return ScreeningResult(
        label: 'INCONCLUSIVE',
        confidence: 0.0,
        reason: 'Screening unavailable — use clinical judgment',
        source: 'stub',
      );
    }
  }

  /// Web-only demo buttons.
  ScreeningResult simulate({required bool forceRed}) =>
      simulatorClassify(forceRed: forceRed);

  Future<void> dispose() async {
    try {
      await _recorder?.dispose();
    } catch (_) {}
    try {
      await _classifier?.dispose();
    } catch (_) {}
    _recorder = null;
    _classifier = null;
  }
}
