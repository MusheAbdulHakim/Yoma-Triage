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
  YamnetClassifier? _secondary;
  bool _cancelled = false;

  bool get isWebSimulator => kIsWeb;

  Future<void> startRecording() async {
    if (kIsWeb) return;
    if (ScreeningConfig.moewsOnly) return;
    _recorder ??= createAudioRecorder();
    await _recorder!.start();
  }

  Future<ScreeningResult> stopAndClassify() async {
    lastDualRunSecondary = null;
    if (kIsWeb) {
      return simulatorClassify(forceRed: false);
    }

    if (ScreeningConfig.moewsOnly) {
      return moewsOnlyResult();
    }

    try {
      final pcm = await (_recorder ?? createAudioRecorder()).stop();
      if (_cancelled) return cancelledResult();
      _classifier ??= await createConfiguredClassifier();
      if (_cancelled) return cancelledResult();
      final primary = await _classifier!.classifyPcm16kHzMono(pcm);
      if (_cancelled) return cancelledResult();

      if (ScreeningConfig.dualRunYamnet &&
          ScreeningConfig.model != 'yamnet' &&
          ScreeningConfig.model != 'stub') {
        try {
          final yamnet = _secondary = await createYamnetClassifier();
          if (!_cancelled) lastDualRunSecondary = await yamnet.classifyPcm16kHzMono(pcm);
          await yamnet.dispose();
        } catch (_) {
          // Dual-run is best-effort; primary result still used.
        } finally {
          _secondary = null;
        }
      }
      return primary;
    } catch (e) {
      if (e.toString().contains('permission')) {
        return unavailableResult(
          reason: 'Mic permission denied — use Emergency Referral bypass',
        );
      }
      return unavailableResult();
    }
  }

  /// The CHO tapped Cancel during analysis, or left the screen. Stops the model where it
  /// is; [stopAndClassify] then returns [cancelledResult].
  void cancelAnalysis() {
    _cancelled = true;
    _classifier?.cancel();
    _secondary?.cancel();
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
