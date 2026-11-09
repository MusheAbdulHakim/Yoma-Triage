import 'dart:typed_data';

import 'audio_recorder_base.dart';

/// Web / unsupported platforms: no microphone — returns silence.
class AudioRecorderStub implements AudioRecorderService {
  @override
  Future<void> start() async {}

  @override
  Future<Uint8List> stop() async => Uint8List(0);

  @override
  Future<void> dispose() async {}

  @override
  Stream<double> levels() => const Stream.empty();
}

AudioRecorderService createAudioRecorder() => AudioRecorderStub();

/// No files are written on these platforms, so there is nothing to purge.
Future<int> purgeStaleRecordings() async => 0;
