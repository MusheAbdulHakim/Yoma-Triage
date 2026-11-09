import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:yoma_triage/config.dart';
import 'package:yoma_triage/screens/result_screen.dart';
import 'package:yoma_triage/screens/screening_screen.dart';
import 'package:yoma_triage/screens/vitals_screen.dart';
import 'package:yoma_triage/services/audio_recorder_io.dart';
import 'package:yoma_triage/services/moews_calculator.dart';
import 'package:yoma_triage/services/screening_model_factory.dart';
import 'package:yoma_triage/services/screening_result.dart';
import 'package:yoma_triage/services/screening_service.dart';
import 'package:yoma_triage/services/tflite_output.dart';
import 'package:yoma_triage/services/yamnet_classifier_io.dart';

class _FakeRecorder implements AudioRecorder {
  bool recording = false;
  bool throwOnStop = false;
  String? path;

  @override
  Future<bool> hasPermission({bool request = true}) async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    this.path = path;
    await File(path).writeAsBytes(Uint8List(64));
    recording = true;
  }

  @override
  Future<bool> isRecording() async => recording;

  @override
  Future<String?> stop() async {
    recording = false;
    if (throwOnStop) throw StateError('stop failed');
    return path;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MicFailsService extends ScreeningService {
  @override
  Future<void> startRecording() async => throw StateError('no microphone');
}

/// Mirrors the plugin's Tensor.copyTo: shapes must match, then items are copied.
void copyLikePlugin(List tensorOutput, List dst) {
  expect(tensorOutput.shape, dst.shape);
  for (var i = 0; i < tensorOutput.length; i++) {
    dst[i] = tensorOutput[i];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('output buffer shape', () {
    for (final size in [521, 1280]) {
      test('[1, $size] tensor copies into the buffer and reads from [0]', () {
        final bytes = Uint8List(size * 4);
        ByteData.sublistView(bytes).setFloat32(4, 0.75, Endian.little);
        final tensorOutput = ByteConversionUtils.convertBytesToObject(
          bytes,
          TensorType.float32,
          [1, size],
        ) as List;

        final buffer = singleBatchOutput(size);
        copyLikePlugin(tensorOutput, buffer);

        expect(buffer[0].length, size);
        expect(buffer[0][1], 0.75);
      });
    }

    test('a flat buffer is what the plugin rejects', () {
      final tensorOutput = ByteConversionUtils.convertBytesToObject(
        Uint8List(521 * 4),
        TensorType.float32,
        [1, 521],
      ) as List;
      expect(
        tensorOutput.shape,
        isNot(List<double>.filled(521, 0.0).shape),
      );
    });
  });

  group('fail-safe results', () {
    test('YAMNet that cannot load returns INCONCLUSIVE, not GREEN', () async {
      // No native TFLite library on the test host, so load fails for real.
      final classifier = await createYamnetClassifier();
      final result = await classifier.classifyPcm16kHzMono(Uint8List(32000));
      expect(result.label, 'INCONCLUSIVE');
      expect(result.source, 'unavailable');
    });

    test('stub classifier is INCONCLUSIVE', () {
      expect(stubClassify().label, 'INCONCLUSIVE');
    });

    test('recorder failure in the service returns INCONCLUSIVE', () async {
      final result = await ScreeningService(
        recorder: AudioRecorderIo(recorder: _FakeRecorder()..recording = true
          ..throwOnStop = true),
      ).stopAndClassify();
      expect(result.label, 'INCONCLUSIVE');
    });

    test('configured classifier never yields GREEN by default', () async {
      final classifier = await createConfiguredClassifier();
      final result = await classifier.classifyPcm16kHzMono(Uint8List(0));
      expect(result.label, 'INCONCLUSIVE');
    });

    testWidgets('mic failure on the screen ends INCONCLUSIVE', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreeningScreen(
            forceWebSimulator: false,
            service: _MicFailsService(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Not a permission problem, so no Open settings; Skip to vitals is the way on.
      expect(find.text('The microphone could not start'), findsOneWidget);
      expect(find.byKey(const Key('screening_open_settings')), findsNothing);

      await tester.tap(find.byKey(const Key('screening_skip_to_vitals')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      final result = tester.widget<VitalsScreen>(find.byType(VitalsScreen)).result;
      expect(result.label, 'INCONCLUSIVE');
      expect(result.source, 'unavailable');
    });
  });

  group('MOEWS_ONLY default', () {
    test('acoustic screening is off unless explicitly enabled', () {
      const explicitlyEnabled =
          String.fromEnvironment('MOEWS_ONLY') == 'false';
      expect(ScreeningConfig.moewsOnly, !explicitlyEnabled);
    });

    testWidgets('disabled acoustic result shows no acoustic card',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResultScreen(
            result: moewsOnlyResult(),
            moews: const MoewsResult(score: 0, riskLevel: 'GREEN'),
          ),
        ),
      );
      expect(find.text('Breathing check (advisory)'), findsNothing);
      expect(find.text('Refer with clinical judgment'), findsOneWidget);
    });
  });

  group('recording cleanup', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('yoma_audit'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('dispose deletes the WAV when recording was abandoned', () async {
      final fake = _FakeRecorder();
      final recorder =
          AudioRecorderIo(recorder: fake, tempDirectory: () async => dir);
      await recorder.start();
      expect(File(fake.path!).existsSync(), isTrue);

      await recorder.dispose();

      expect(File(fake.path!).existsSync(), isFalse);
    });

    test('dispose still deletes the WAV if stopping throws', () async {
      final fake = _FakeRecorder()..throwOnStop = true;
      final recorder =
          AudioRecorderIo(recorder: fake, tempDirectory: () async => dir);
      await recorder.start();

      await recorder.dispose();

      expect(File(fake.path!).existsSync(), isFalse);
    });

    test('stop returns bytes and deletes the WAV', () async {
      final fake = _FakeRecorder();
      final recorder =
          AudioRecorderIo(recorder: fake, tempDirectory: () async => dir);
      await recorder.start();

      final bytes = await recorder.stop();

      expect(bytes.length, 64);
      expect(File(fake.path!).existsSync(), isFalse);
    });

    test('startup purge removes only stale recordings', () async {
      final stale = File('${dir.path}/yoma_triage_breath_1.wav')
        ..writeAsBytesSync([1]);
      final other = File('${dir.path}/unrelated.wav')..writeAsBytesSync([1]);

      expect(await purgeStaleRecordings(directory: dir), 1);

      expect(stale.existsSync(), isFalse);
      expect(other.existsSync(), isTrue);
    });
  });
}
