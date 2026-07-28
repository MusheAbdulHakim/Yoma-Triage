import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio_recorder_base.dart';

/// Native (Android/iOS) recorder: 16 kHz mono PCM via `record`.
class AudioRecorderIo implements AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  @override
  Future<void> start() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      throw StateError('Microphone permission denied');
    }
    final dir = await getTemporaryDirectory();
    _path = p.join(
      dir.path,
      'yoma_triage_breath_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  @override
  Future<Uint8List> stop() async {
    if (!await _recorder.isRecording()) {
      return Uint8List(0);
    }
    final path = await _recorder.stop();
    final filePath = path ?? _path;
    if (filePath == null) return Uint8List(0);
    final file = File(filePath);
    if (!await file.exists()) return Uint8List(0);
    final bytes = await file.readAsBytes();
    try {
      await file.delete();
    } catch (_) {}
    return bytes;
  }

  @override
  Future<void> dispose() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    await _recorder.dispose();
  }
}

AudioRecorderService createAudioRecorder() => AudioRecorderIo();
