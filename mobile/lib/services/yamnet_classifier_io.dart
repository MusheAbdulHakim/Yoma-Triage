import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'screening_result.dart';
import 'yamnet_classifier_base.dart';

/// Native (Android/iOS): real YAMNet when asset loads and tensors match; otherwise stub.
class YamnetClassifierIo implements YamnetClassifier {
  YamnetClassifierIo._live(this._interpreter, this._inputSize, this._outputSize);

  final Interpreter _interpreter;
  final int _inputSize;
  final int _outputSize;

  /// AudioSet YAMNet class indices for cough / wheeze / breathing / gasp.
  /// See yamnet_class_map.csv (Google AudioSet).
  static const _respiratoryClassIndices = <int>{
    36, // Breathing
    37, // Wheeze
    39, // Gasp
    40, // Pant
    41, // Snort
    42, // Cough
  };

  static Future<YamnetClassifier> create({bool forceRed = false}) async {
    try {
      await rootBundle.load('assets/models/yamnet.tflite');
      final interpreter =
          await Interpreter.fromAsset('assets/models/yamnet.tflite');
      final inTensors = interpreter.getInputTensors();
      final outTensors = interpreter.getOutputTensors();
      if (inTensors.isEmpty || outTensors.isEmpty) {
        interpreter.close();
        return _StubWithFlag(forceRed: forceRed);
      }
      final inputSize = inTensors.first.shape.isEmpty
          ? 15600
          : inTensors.first.shape.reduce((a, b) => a * b);
      final outputSize = outTensors.first.shape.isEmpty
          ? 521
          : outTensors.first.shape.reduce((a, b) => a * b);
      if (inputSize <= 0 || outputSize <= 0) {
        interpreter.close();
        return _StubWithFlag(forceRed: forceRed);
      }
      // Probe once with zeros — if native run fails, fall back to stub.
      try {
        final probeIn = List<double>.filled(inputSize, 0.0);
        final probeOut = List<double>.filled(outputSize, 0.0);
        interpreter.run(probeIn, probeOut);
      } catch (_) {
        try {
          interpreter.close();
        } catch (_) {}
        return _StubWithFlag(forceRed: forceRed);
      }
      return YamnetClassifierIo._live(interpreter, inputSize, outputSize);
    } catch (_) {
      return _StubWithFlag(forceRed: forceRed);
    }
  }

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    try {
      final samples = _pcm16ToFloat(_stripWavHeader(pcmBytes));
      if (samples.isEmpty) {
        return mapYamnetToResult(abnormalScore: 0.4);
      }

      var maxAbnormal = 0.0;
      var offset = 0;
      final input = List<double>.filled(_inputSize, 0.0);
      final output = List<double>.filled(_outputSize, 0.0);

      while (offset + _inputSize <= samples.length) {
        for (var i = 0; i < _inputSize; i++) {
          input[i] = samples[offset + i];
        }
        _interpreter.run(input, output);
        final abnormal = _abnormalScore(output);
        if (abnormal > maxAbnormal) maxAbnormal = abnormal;
        offset += _inputSize ~/ 2;
      }

      if (offset == 0) {
        for (var i = 0; i < _inputSize; i++) {
          input[i] = i < samples.length ? samples[i] : 0.0;
        }
        _interpreter.run(input, output);
        maxAbnormal = _abnormalScore(output);
      }

      return mapYamnetToResult(abnormalScore: maxAbnormal);
    } catch (_) {
      return ScreeningResult(
        label: 'INCONCLUSIVE',
        confidence: 0.0,
        reason: 'Screening unavailable — use clinical judgment',
        source: 'stub',
      );
    }
  }

  double _abnormalScore(List<double> scores) {
    if (scores.isEmpty) return 0.0;

    var maxRespiratory = 0.0;
    for (final idx in _respiratoryClassIndices) {
      if (idx < scores.length && scores[idx] > maxRespiratory) {
        maxRespiratory = scores[idx];
      }
    }
    if (maxRespiratory > 0) return maxRespiratory;

    // Fallback when label layout differs: top-5 class average.
    final sorted = List<double>.from(scores)..sort();
    final top = sorted.reversed.take(5).toList();
    return top.reduce((a, b) => a + b) / top.length;
  }

  /// Skip RIFF/WAV header if present so PCM samples start correctly.
  Uint8List _stripWavHeader(Uint8List bytes) {
    if (bytes.length > 44 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      // Find 'data' chunk.
      for (var i = 12; i + 8 < bytes.length; i++) {
        if (bytes[i] == 0x64 &&
            bytes[i + 1] == 0x61 &&
            bytes[i + 2] == 0x74 &&
            bytes[i + 3] == 0x61) {
          final dataStart = i + 8;
          if (dataStart < bytes.length) {
            return Uint8List.sublistView(bytes, dataStart);
          }
        }
      }
      return Uint8List.sublistView(bytes, 44);
    }
    return bytes;
  }

  List<double> _pcm16ToFloat(Uint8List bytes) {
    if (bytes.length < 2) return const [];
    final bd = ByteData.sublistView(bytes);
    final out = <double>[];
    final limit = bytes.length - (bytes.length % 2);
    for (var i = 0; i < limit; i += 2) {
      final sample = bd.getInt16(i, Endian.little);
      out.add(sample / 32768.0);
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    try {
      _interpreter.close();
    } catch (_) {}
  }
}

class _StubWithFlag implements YamnetClassifier {
  _StubWithFlag({required this.forceRed});
  final bool forceRed;

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async =>
      stubClassify(forceRed: forceRed);

  @override
  Future<void> dispose() async {}
}

Future<YamnetClassifier> createYamnetClassifier({bool forceRed = false}) =>
    YamnetClassifierIo.create(forceRed: forceRed);
