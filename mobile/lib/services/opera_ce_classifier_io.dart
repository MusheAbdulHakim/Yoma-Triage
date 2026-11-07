import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'audio_pcm.dart';
import 'background_job.dart';
import 'opera_ce_head_map.dart';
import 'opera_ce_mel.dart';
import 'screening_result.dart';
import 'tflite_output.dart';
import 'yamnet_classifier_base.dart';

export 'opera_ce_head_map.dart' show mapOperaCeHeadToResult;

/// Native OPERA-CE path: Dart mel → encoder TFLite → optional head.
///
/// Without a trained head (`opera_ce_head.tflite`), always returns
/// **INCONCLUSIVE** after a successful encoder forward — never invents
/// GREEN/RED from embeddings alone.
///
/// Like YAMNet, loading and inference run in a background isolate, so the main thread
/// never stalls.
class OperaCeClassifierIo implements YamnetClassifier {
  OperaCeClassifierIo._(this._models);

  static const encoderAsset = 'assets/models/opera_ce_encoder.tflite';
  static const headAsset = 'assets/models/opera_ce_head.tflite';
  static const modelVersionEncoderOnly = 'opera-ce-encoder-v0';
  static const modelVersionWithHead = 'opera-ce-head-v0';

  final OperaCeModels _models;
  BackgroundJob<ScreeningResult>? _job;

  static Future<YamnetClassifier> create() async {
    final Uint8List encoder;
    try {
      encoder = await _loadAsset(encoderAsset);
    } catch (_) {
      return OperaCeUnavailable(_operaPending());
    }
    Uint8List? head;
    try {
      head = await _loadAsset(headAsset);
    } catch (_) {
      head = null;
    }
    try {
      final models = await BackgroundJob.start(
        () => _probeOperaCe(encoder, head),
        name: 'opera-ce-load',
      ).result;
      return OperaCeClassifierIo._(models);
    } catch (_) {
      return OperaCeUnavailable(_operaPending());
    }
  }

  static Future<Uint8List> _loadAsset(String name) async {
    final data = await rootBundle.load(name);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async {
    final job = _startClassifying(_models, pcmBytes);
    _job = job;
    try {
      return await job.result;
    } on JobCancelled {
      return cancelledResult();
    } catch (_) {
      return _operaUnavailable();
    } finally {
      if (identical(_job, job)) _job = null;
    }
  }

  @override
  void cancel() => _job?.cancel();

  @override
  Future<void> dispose() async => cancel();
}

/// What a background isolate needs to run OPERA-CE: the model files and tensor sizes.
class OperaCeModels {
  OperaCeModels({
    required this.encoder,
    required this.encoderInputSize,
    required this.encoderOutputSize,
    this.head,
    this.headInputSize,
    this.headOutputSize,
  });

  final Uint8List encoder;
  final int encoderInputSize;
  final int encoderOutputSize;
  final Uint8List? head;
  final int? headInputSize;
  final int? headOutputSize;
}

ScreeningResult _operaPending() => ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: 'opera_ce encoder pack not installed — use MOEWS and clinical judgment',
      source: 'opera_ce',
      modelVersion: 'opera_ce-pending',
    );

ScreeningResult _operaUnavailable() => ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: 'OPERA-CE screening unavailable — use clinical judgment',
      source: 'opera_ce',
      modelVersion: OperaCeClassifierIo.modelVersionEncoderOnly,
    );

/// Top level, so the closure sent to the isolate can't capture the classifier.
BackgroundJob<ScreeningResult> _startClassifying(OperaCeModels models, Uint8List pcmBytes) =>
    BackgroundJob.start(() => _classifyInBackground(models, pcmBytes), name: 'opera-ce');

int _size(List<int> shape, int fallback) =>
    shape.isEmpty ? fallback : shape.reduce((a, b) => a * b);

/// Loads the encoder, and the head if there is one, and runs each once on zeros.
OperaCeModels _probeOperaCe(Uint8List encoderModel, Uint8List? headModel) {
  final encoder = Interpreter.fromBuffer(encoderModel);
  try {
    final inTensors = encoder.getInputTensors();
    final outTensors = encoder.getOutputTensors();
    if (inTensors.isEmpty || outTensors.isEmpty) {
      throw StateError('OPERA-CE encoder has no input or output tensor');
    }
    final inSize = _size(inTensors.first.shape, OperaCeMel.melFrames * OperaCeMel.melBins);
    final outSize = _size(outTensors.first.shape, 1280);
    encoder.run(List<double>.filled(inSize, 0.0), singleBatchOutput(outSize));

    if (headModel != null) {
      try {
        final head = Interpreter.fromBuffer(headModel);
        try {
          final hIn = _size(head.getInputTensors().first.shape, 0);
          final hOut = _size(head.getOutputTensors().first.shape, 0);
          head.run(List<double>.filled(hIn, 0.0), singleBatchOutput(hOut));
          return OperaCeModels(
            encoder: encoderModel,
            encoderInputSize: inSize,
            encoderOutputSize: outSize,
            head: headModel,
            headInputSize: hIn,
            headOutputSize: hOut,
          );
        } finally {
          head.close();
        }
      } catch (_) {
        // A head that won't run is ignored: the encoder alone stays INCONCLUSIVE.
      }
    }
    return OperaCeModels(
      encoder: encoderModel,
      encoderInputSize: inSize,
      encoderOutputSize: outSize,
    );
  } finally {
    encoder.close();
  }
}

ScreeningResult _classifyInBackground(OperaCeModels models, Uint8List pcmBytes) {
  final samples = pcm16ToFloat(stripWavHeader(pcmBytes));
  if (samples.isEmpty) {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason: 'Empty audio — use clinical judgment',
      source: 'opera_ce',
      modelVersion: OperaCeClassifierIo.modelVersionEncoderOnly,
    );
  }

  final mel = OperaCeMel.melForEncoder(samples);
  final input = List<double>.filled(models.encoderInputSize, 0.0);
  final n = mel.length < models.encoderInputSize ? mel.length : models.encoderInputSize;
  for (var i = 0; i < n; i++) {
    input[i] = mel[i];
  }
  final encoder = Interpreter.fromBuffer(models.encoder);
  final List<double> embedding;
  try {
    final encoderOutput = singleBatchOutput(models.encoderOutputSize);
    encoder.run(input, encoderOutput);
    embedding = encoderOutput[0];
  } finally {
    encoder.close();
  }

  final headModel = models.head;
  final headInputSize = models.headInputSize;
  final headOutputSize = models.headOutputSize;
  if (headModel == null || headInputSize == null || headOutputSize == null) {
    return ScreeningResult(
      label: 'INCONCLUSIVE',
      confidence: 0.0,
      reason:
          'OPERA-CE encoder OK; classifier head not trained — use MOEWS and clinical judgment',
      source: 'opera_ce',
      modelVersion: OperaCeClassifierIo.modelVersionEncoderOnly,
    );
  }

  final headInput = List<double>.filled(headInputSize, 0.0);
  final copy = embedding.length < headInputSize ? embedding.length : headInputSize;
  for (var i = 0; i < copy; i++) {
    headInput[i] = embedding[i];
  }
  final head = Interpreter.fromBuffer(headModel);
  try {
    final headOutput = singleBatchOutput(headOutputSize);
    head.run(headInput, headOutput);
    return mapOperaCeHeadToResult(headOutput[0]);
  } finally {
    head.close();
  }
}

/// OPERA-CE can't run here, for the reason in [result].
class OperaCeUnavailable implements YamnetClassifier {
  OperaCeUnavailable(this.result);

  final ScreeningResult result;

  @override
  Future<ScreeningResult> classifyPcm16kHzMono(Uint8List pcmBytes) async => result;

  @override
  void cancel() {}

  @override
  Future<void> dispose() async {}
}

Future<YamnetClassifier> createOperaCeClassifier() =>
    OperaCeClassifierIo.create();
