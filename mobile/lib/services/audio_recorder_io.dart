import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio_recorder_base.dart';

const _recordingPrefix = 'yoma_triage_breath_';

/// Native (Android/iOS) recorder: 16 kHz mono PCM via `record`.
class AudioRecorderIo implements AudioRecorderService {
  AudioRecorderIo({
    AudioRecorder? recorder,
    Future<Directory> Function()? tempDirectory,
  })  : _recorder = recorder ?? AudioRecorder(),
        _tempDirectory = tempDirectory ?? getTemporaryDirectory;

  final AudioRecorder _recorder;
  final Future<Directory> Function() _tempDirectory;
  String? _path;

  @override
  Future<void> start() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      throw StateError('Microphone permission denied');
    }
    final dir = await _tempDirectory();
    _path = p.join(
      dir.path,
      '$_recordingPrefix${DateTime.now().millisecondsSinceEpoch}.wav',
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
      await _deleteRecording();
      return Uint8List(0);
    }
    final path = await _recorder.stop();
    final filePath = path ?? _path;
    if (filePath == null) return Uint8List(0);
    final file = File(filePath);
    if (!await file.exists()) return Uint8List(0);
    final bytes = await file.readAsBytes();
    await _deleteRecording(filePath);
    return bytes;
  }

  @override
  Future<void> dispose() async {
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } catch (_) {}
    await _deleteRecording();
    await _recorder.dispose();
  }

  Future<void> _deleteRecording([String? path]) async {
    final target = path ?? _path;
    _path = null;
    if (target == null) return;
    try {
      await File(target).delete();
    } catch (_) {}
  }
}

AudioRecorderService createAudioRecorder() => AudioRecorderIo();

/// Removes recordings left behind by a crash or kill. Returns how many it removed.
Future<int> purgeStaleRecordings({Directory? directory}) async {
  var removed = 0;
  try {
    final dir = directory ?? await getTemporaryDirectory();
    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (entity is File &&
          name.startsWith(_recordingPrefix) &&
          name.endsWith('.wav')) {
        await entity.delete();
        removed++;
      }
    }
  } catch (_) {
    // Best effort: a purge failure must never stop the app from starting.
  }
  return removed;
}
