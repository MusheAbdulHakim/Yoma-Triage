import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'opera_ce_head_map.dart';
import 'opera_ce_mel.dart';
import 'screening_result.dart';
import 'yamnet_classifier_base.dart';

export 'opera_ce_head_map.dart' show mapOperaCeHeadToResult;

/// Native OPERA-CE path: Dart mel → encoder TFLite → optional head.
///
/// Without a trained head (`opera_ce_head.tflite`), always returns
/// **INCONCLUSIVE** after a successful encoder forward — never invents
/// GREEN/RED from embeddings alone.
class OperaCeClassifierIo implements YamnetClassifier {
  OperaCeClassifierIo._({
    required Interpreter encoder,
    required this.encoderInputSize,
    required this.encoderOutputSize,
    Interpreter? head,
    this.headInputSize,
    this.headOutputSize,
  })  : _encoder = encoder,
        _head = head;

  final Interpreter _encoder;
  final Interpreter? _head;
  final int encoderInputSize;
  final int encoderOutputSize;
  final int? headInputSize;
  final int? headOutputSize;

  static const encoderAsset = 'assets/models/opera_ce_encoder.tflite';
  static const headAsset = 'assets/models/opera_ce_head.tflite';
  static const modelVersionEncoderOnly = 'opera-ce-encoder-v0';
  static const modelVersionWithHead = 'opera-ce-head-v0';

  static Future<YamnetClassifier> create() async {
    try {
      await rootBundle.load(encoderAsset);
    } catch (_) {
      return _OperaPending();
    }

    Interpreter? encoder;
    Interpreter? head;
    try {
      encoder = await Interpreter.fromAsset(encoderAsset);
      final inTensors = encoder.getInputTensors();
      final outTensors = encoder.getOutputTensors();
      if (inTensors.isEmpty || outTensors.isEmpty) {
        encoder.close();
        return _OperaPending();
      }
      final inSize = inTensors.first.shape.isEmpty
          ? OperaCeMel.melFrames * OperaCeMel.melBins
          : inTensors.first.shape.reduce((a, b) => a * b);
      final outSize = outTensors.first.shape.isEmpty
          ? 1280
          : outTensors.first.shape.reduce((a, b) => a * b);

      final probeIn = List<double>.filled(inSize, 0.0);
      final probeOut = List<double>.filled(outSize, 0.0);
      encoder.run(probeIn, probeOut);

      try {
        await rootBundle.load(headAsset);
        head = await Interpreter.fromAsset(headAsset);
        final hIn = head.getInputTensors().first.shape.reduce((a, b) => a * b);
        final hOut =
            head.getOutputTensors().first.shape.reduce((a, b) => a * b);
        final hProbeIn = List<double>.filled(hIn, 0.0);
        final hProbeOut = List<double>.filled(hOut, 0.0);
        head.run(hProbeIn, hProbeOut);
        return OperaCeClassifierIo._(
          encoder: encoder,
          encoderInputSize: inSize,
          encoderOutputSize: outSize,
          head: head,
          headInputSize: hIn,
          headOutputSize: hOut,
        );
      } catch (_) {
        try {
          head?.close();
        } catch (_) {}
        head = null;
      }

      return OperaCeClassifierIo._(
        encoder: encoder,
        encoderInputSize: inSize,
        encoderOutputSize: outSize,
      );
    } catch (_) {
      try {
        encoder?.close();
      } catch (_) {}
      try {
        head?.close();
      } catch (_) {}
      return _OperaPending();
    }
  }

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    try {
      final samples = _pcm16ToFloat(_stripWavHeader(pcmBytes));
      if (samples.isEmpty) {
        return ScreeningResult(
          label: 'INCONCLUSIVE',
          confidence: 0.0,
          reason: 'Empty audio — use clinical judgment',
          source: 'opera_ce',
          modelVersion: modelVersionEncoderOnly,
        );
      }

      final mel = OperaCeMel.melForEncoder(samples);
      final input = List<double>.filled(encoderInputSize, 0.0);
      final n = mel.length < encoderInputSize ? mel.length : encoderInputSize;
      for (var i = 0; i < n; i++) {
        input[i] = mel[i];
      }
      final embedding = List<double>.filled(encoderOutputSize, 0.0);
      _encoder.run(input, embedding);

      final head = _head;
      if (head == null || headInputSize == null || headOutputSize == null) {
        return ScreeningResult(
          label: 'INCONCLUSIVE',
          confidence: 0.0,
          reason:
              'OPERA-CE encoder OK; classifier head not trained — use MOEWS and clinical judgment',
          source: 'opera_ce',
          modelVersion: modelVersionEncoderOnly,
        );
      }

      final hIn = List<double>.filled(headInputSize!, 0.0);
      final copy = embedding.length < headInputSize!
          ? embedding.length
          : headInputSize!;
      for (var i = 0; i < copy; i++) {
        hIn[i] = embedding[i];
      }
      final logits = List<double>.filled(headOutputSize!, 0.0);
      head.run(hIn, logits);
      return mapOperaCeHeadToResult(logits);
    } catch (_) {
      return ScreeningResult(
        label: 'INCONCLUSIVE',
        confidence: 0.0,
        reason: 'OPERA-CE screening unavailable — use clinical judgment',
        source: 'opera_ce',
        modelVersion: modelVersionEncoderOnly,
      );
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _encoder.close();
    } catch (_) {}
    try {
      _head?.close();
    } catch (_) {}
  }

  Uint8List _stripWavHeader(Uint8List bytes) {
    if (bytes.length > 44 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
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
      out.add(bd.getInt16(i, Endian.little) / 32768.0);
    }
    return out;
  }
}

class _OperaPending implements YamnetClassifier {
  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason:
          'opera_ce encoder pack not installed — use MOEWS and clinical judgment',
      source: 'opera_ce',
      modelVersion: 'opera_ce-pending',
    );
  }

  @override
  Future<void> dispose() async {}
}

Future<YamnetClassifier> createOperaCeClassifier() =>
    OperaCeClassifierIo.create();
