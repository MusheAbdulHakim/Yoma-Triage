import 'package:flutter/foundation.dart' show kIsWeb;

import '../config.dart';
import 'audio_recorder.dart';
import 'screening_model_factory.dart';
import 'screening_result.dart';
import 'yamnet_classifier.dart';

/// Facade: web simulator vs native record + configured screening model.
class ScreeningService {
  ScreeningService({
    YamnetClassifier? classifier,
    AudioRecorderService? recorder,
  })  : _classifier = classifier,
        _recorder = recorder;

  YamnetClassifier? _classifier;
  AudioRecorderService? _recorder;
  ScreeningResult? lastDualRunSecondary;

  bool get isWebSimulator => kIsWeb;

  Future<void> startRecording() async {
    if (kIsWeb) return;
    if (ScreeningConfig.moewsOnly) return;
    _recorder ??= createAudioRecorder();
    await _recorder!.start();
  }

  Future<ScreeningResult> stopAndClassify({bool forceRed = false}) async {
    lastDualRunSecondary = null;
    if (kIsWeb) {
      return simulatorClassify(forceRed: forceRed);
    }

    if (ScreeningConfig.moewsOnly) {
      return ScreeningResult(
        label: 'INCONCLUSIVE',
        confidence: 0.0,
        reason:
            'Acoustic screening disabled (MOEWS_ONLY) — use vitals and judgment',
        source: 'moews_only',
        modelVersion: 'moews-only-v0',
      );
    }

    try {
      final pcm = await (_recorder ?? createAudioRecorder()).stop();
      _classifier ??= await createConfiguredClassifier(forceRed: forceRed);
      final primary = await _classifier!.classifyPcm16kHzMono(pcm);

      if (ScreeningConfig.dualRunYamnet &&
          ScreeningConfig.model != 'yamnet' &&
          ScreeningConfig.model != 'stub') {
        try {
          final yamnet = await createYamnetClassifier(forceRed: forceRed);
          lastDualRunSecondary = await yamnet.classifyPcm16kHzMono(pcm);
          await yamnet.dispose();
        } catch (_) {
          // Dual-run is best-effort; primary result still used.
        }
      }
      return primary;
    } catch (e) {
      if (e.toString().contains('permission')) {
        return ScreeningResult(
          label: 'INCONCLUSIVE',
          confidence: 0.0,
          reason: 'Mic permission denied — use Emergency Referral bypass',
          source: 'stub',
          modelVersion: 'stub-v0',
        );
      }
      return ScreeningResult(
        label: 'INCONCLUSIVE',
        confidence: 0.0,
        reason: 'Screening unavailable — use clinical judgment',
        source: 'stub',
        modelVersion: 'stub-v0',
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
