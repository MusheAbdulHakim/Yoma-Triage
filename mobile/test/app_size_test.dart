// A5: the app bundles only the model it uses. OPERA-CE stays in the code but isn't
// bundled, and its message says why it's INCONCLUSIVE.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoma_triage/services/opera_ce_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pubspec bundles YAMNet and the catalog, and nothing else from assets/models', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final assets = RegExp(r'^\s+- (assets/\S+)', multiLine: true)
        .allMatches(pubspec)
        .map((m) => m.group(1))
        .toList();
    expect(assets, ['assets/models/yamnet.tflite', 'assets/catalog/northern_bootstrap.json']);
  });

  test('the OPERA-CE files are kept in the repo for the export script', () {
    expect(File('assets/models/opera_ce_encoder.tflite').existsSync(), isTrue);
    expect(File('assets/models/opera_ce_encoder.onnx').existsSync(), isTrue);
  });

  test('without its files, OPERA-CE says it is not in this build', () async {
    final classifier = await createOperaCeClassifier();
    final result = await classifier.classifyPcm16kHzMono(Uint8List(32000));
    expect(result.label, 'INCONCLUSIVE');
    expect(result.reason, contains('not included in this build'));
    expect(result.reason, isNot(contains('not installed')));
  });

  test('with its files but a model that won\'t start, it says that instead', () async {
    // The encoder is "bundled" here, but this test host has no TFLite library, so it
    // fails to load for real: the same path as the encoder that fails on Android.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/models/opera_ce_encoder.tflite') {
        return ByteData.sublistView(Uint8List.fromList([1, 2, 3, 4]));
      }
      return null;
    });
    addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));

    final classifier = await createOperaCeClassifier();
    final result = await classifier.classifyPcm16kHzMono(Uint8List(32000));
    expect(result.label, 'INCONCLUSIVE');
    expect(result.reason, contains('could not start on this phone'));
  });
}
