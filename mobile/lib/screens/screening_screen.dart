import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/screening_result.dart';
import '../services/screening_service.dart';
import '../theme/yoma_theme.dart';
import '../widgets/breathing_pulse.dart';
import 'vitals_screen.dart';

class ScreeningScreen extends StatefulWidget {
  /// When non-null, overrides [kIsWeb] so widget tests can exercise the simulator.
  final bool? forceWebSimulator;

  const ScreeningScreen({super.key, this.forceWebSimulator});

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  late int _remaining = ScreeningConfig.durationSec;
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
      unawaited(_beginNativeCapture());
    }
  }

  Future<void> _beginNativeCapture() async {
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
        // Brief pause so the breath pulse is visible in the web demo.
        await Future<void>.delayed(const Duration(milliseconds: 700));
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
    // Result ready — stop the pulse immediately, then leave the screen.
    setState(() {
      _analyzing = false;
      _recording = false;
    });
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => VitalsScreen(result: result)),
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
        child: _isWebSimulator ? _buildWebSimulator() : _buildNativeCapture(),
      ),
    );
  }

  String get _nativeStatusText {
    if (_analyzing) return 'Checking breath…';
    if (_recording) return 'Listening… $_remaining s left';
    return _error ?? 'Starting microphone…';
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
          'On Android and iOS, YAMNet uses the microphone. '
          'On web, use these buttons to simulate screening.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const Spacer(),
        if (_analyzing) ...[
          const Center(
            child: BreathingPulse(
              active: true,
              child: Text(
                'Checking…',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: YomaColors.brand,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: YomaColors.safe,
          ),
          onPressed: _analyzing ? null : () => _finish(forceRed: false),
          child: Text(_analyzing ? 'Checking…' : 'Demo Normal'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: YomaColors.danger,
          ),
          onPressed: _analyzing ? null : () => _finish(forceRed: true),
          child: Text(_analyzing ? 'Checking…' : 'Demo Code Red'),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildNativeCapture() {
    final pulsing = _recording || _analyzing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Hold phone near chest',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          _nativeStatusText,
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
          child: BreathingPulse(
            active: pulsing,
            child: Text(
              _analyzing ? '…' : '$_remaining',
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.bold,
                color: YomaColors.brand,
              ),
            ),
          ),
        ),
        const Spacer(),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: _analyzing ? null : () => _finish(forceRed: false),
          child: Text(_analyzing ? 'Checking breath…' : 'Stop & Analyze Early'),
        ),
      ],
    );
  }
}
