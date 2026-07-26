import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/screening_result.dart';
import '../services/screening_service.dart';
import 'result_screen.dart';

class ScreeningScreen extends StatefulWidget {
  /// When non-null, overrides [kIsWeb] so widget tests can exercise the simulator.
  final bool? forceWebSimulator;

  const ScreeningScreen({super.key, this.forceWebSimulator});

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  static const _durationSec = 15;
  int _remaining = _durationSec;
  Timer? _timer;
  bool _analyzing = false;
  bool _recording = false;
  bool _finishing = false;
  String? _error;
  final _screening = ScreeningService();

  bool get _isWebSimulator => widget.forceWebSimulator ?? kIsWeb;

  @override
  void initState() {
    super.initState();
    if (!_isWebSimulator) {
      unawaited(_beginAndroidCapture());
    }
  }

  Future<void> _beginAndroidCapture() async {
    try {
      await _screening.startRecording();
      if (!mounted || _finishing) return;
      setState(() => _recording = true);
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _recording = false;
      });
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _finishing) {
        t.cancel();
        return;
      }
      if (_remaining <= 1) {
        t.cancel();
        unawaited(_finish(forceRed: false));
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  Future<void> _finish({required bool forceRed}) async {
    if (_analyzing || _finishing) return;
    _finishing = true;
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _analyzing = true);

    ScreeningResult result;
    try {
      if (_isWebSimulator) {
        result = _screening.simulate(forceRed: forceRed);
      } else if (_error != null || !_recording) {
        result = stubClassify(forceRed: forceRed);
      } else {
        result = await _screening.stopAndClassify(forceRed: forceRed);
      }
    } catch (_) {
      result = ScreeningResult(
        label: 'INCONCLUSIVE',
        confidence: 0.0,
        reason: 'Screening unavailable — use clinical judgment',
        source: 'stub',
      );
    }

    if (!mounted) {
      unawaited(_screening.dispose());
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _finishing = true;
    // Do not dispose the recorder while classify may still be running;
    // stopAndClassify owns stop(); only dispose if we never started finish.
    if (!_analyzing) {
      unawaited(_screening.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Breathing Screen'),
        backgroundColor: const Color(0xFF1A5F7A),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _isWebSimulator ? _buildWebSimulator() : _buildAndroidCapture(),
      ),
    );
  }

  Widget _buildWebSimulator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Web demo simulator',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'YAMNet runs on Android. Use these buttons to simulate screening.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const Spacer(),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: const Color(0xFF2E7D32),
          ),
          onPressed: _analyzing ? null : () => _finish(forceRed: false),
          child: const Text('Demo Normal'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: const Color(0xFFC62828),
          ),
          onPressed: _analyzing ? null : () => _finish(forceRed: true),
          child: const Text('Demo Code Red'),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildAndroidCapture() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Hold phone near chest',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          _recording
              ? 'Recording for $_remaining s (YAMNet or stub if model missing)'
              : (_error ?? 'Starting microphone…'),
          style: TextStyle(color: Colors.grey.shade700),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            'Mic unavailable — use Emergency Referral from Home, or retry stub analyze.',
            style: TextStyle(color: Colors.orange.shade800),
          ),
        ],
        const Spacer(),
        Center(
          child: Text(
            '$_remaining',
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A5F7A),
            ),
          ),
        ),
        const Spacer(),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: _analyzing ? null : () => _finish(forceRed: false),
          child: Text(_analyzing ? 'Analyzing…' : 'Stop & Analyze Early'),
        ),
      ],
    );
  }
}
