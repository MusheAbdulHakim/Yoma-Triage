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
}

AudioRecorderService createAudioRecorder() => AudioRecorderStub();
