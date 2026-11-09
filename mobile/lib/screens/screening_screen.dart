import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/friendly_time.dart';
import '../services/screening_result.dart';
import '../services/screening_service.dart';
import '../theme/yoma_theme.dart';
import '../widgets/breathing_check.dart';
import '../widgets/breathing_pulse.dart';
import 'vitals_screen.dart';

/// What to tell the CHO when the microphone won't start, instead of the exception.
String plainMicrophoneError(Object error) => error.toString().toLowerCase().contains('permission')
    ? 'Microphone permission is off.'
    : 'The microphone could not start.';

/// Below this level the microphone counts as hearing nothing (about -50 dBFS).
const silentLevel = 5 / 35; // -50 dBFS on levelFromDbfs's scale

/// How long the level must stay near silent before the hint shows.
const silenceHintAfter = Duration(seconds: 3);

const silenceHintText = "Can't hear breathing – move the phone closer";

class ScreeningScreen extends StatefulWidget {
  /// When non-null, overrides [kIsWeb] so widget tests can exercise the simulator.
  final bool? forceWebSimulator;

  /// Test seam for microphone and classifier failures.
  final ScreeningService? service;

  /// The Ready step (Start before recording) and the result step (before vitals). Off
  /// unless [ScreeningConfig.breathingSteps]: both add a tap to today's flow.
  final bool? showReadyStep;
  final bool? showResultStep;

  const ScreeningScreen({
    super.key,
    this.forceWebSimulator,
    this.service,
    this.showReadyStep,
    this.showResultStep,
  });

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  final int _total = ScreeningConfig.durationSec;
  late int _remaining = _total;
  Timer? _timer;
  bool _ready = false;
  bool _analyzing = false;
  bool _recording = false;
  bool _finishing = false;
  bool _cancelling = false;
  String? _error;
  bool _permissionError = false;
  ScreeningResult? _result;
  late final ScreeningService _screening = widget.service ?? ScreeningService();

  // Microphone level, for the pulse and the silence hint only.
  final ValueNotifier<double> _level = ValueNotifier(0);
  StreamSubscription<double>? _levelSub;
  Timer? _silenceTimer;
  bool _levelsSeen = false;
  bool _heardSinceTick = false;
  Duration _silentFor = Duration.zero;
  bool _silent = false;
  static const _tick = Duration(milliseconds: 250);

  bool get _isWebSimulator => widget.forceWebSimulator ?? kIsWeb;
  bool get _readyStep => widget.showReadyStep ?? ScreeningConfig.breathingSteps;
  bool get _resultStep => widget.showResultStep ?? ScreeningConfig.breathingSteps;

  @override
  void initState() {
    super.initState();
    if (!_isWebSimulator) {
      if (_readyStep) {
        _ready = true;
      } else {
        unawaited(_beginNativeCapture());
      }
    }
  }

  void _start() {
    setState(() => _ready = false);
    unawaited(_beginNativeCapture());
  }

  Future<void> _beginNativeCapture() async {
    try {
      await _screening.startRecording();
      if (!mounted || _finishing) return;
      setState(() => _recording = true);
      _listenToLevel();
      _startCountdown();
      _announce('Recording. Keep the phone still for $_total seconds.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = plainMicrophoneError(e);
        _permissionError = e.toString().toLowerCase().contains('permission');
        _recording = false;
      });
    }
  }

  /// Display only: never touches the recording or the classifier.
  void _listenToLevel() {
    _silentFor = Duration.zero;
    _levelSub = _screening.microphoneLevels().listen((level) {
      _levelsSeen = true;
      _level.value = _level.value * 0.5 + level * 0.5;
      if (level >= silentLevel) _heardSinceTick = true;
    }, onError: (_) {});
    // Counts quiet time in ticks of its own timer (not the wall clock), so tests can drive it.
    _silenceTimer = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      _silentFor = _heardSinceTick ? Duration.zero : _silentFor + _tick;
      _heardSinceTick = false;
      final silent = _recording && !_analyzing && _levelsSeen && _silentFor >= silenceHintAfter;
      if (silent != _silent) {
        setState(() => _silent = silent);
        if (silent) _announce(silenceHintText);
      }
    });
  }

  void _stopListening() {
    _silenceTimer?.cancel();
    unawaited(_levelSub?.cancel());
    _levelSub = null;
  }

  void _announce(String message) {
    if (!mounted) return;
    unawaited(SemanticsService.sendAnnouncement(View.of(context), message, TextDirection.ltr));
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
      // Every 5 seconds, not every second.
      if (_remaining % 5 == 0) _announce('$_remaining seconds left');
    });
  }

  Future<void> _finish({required bool forceRed}) async {
    if (_analyzing || _finishing) return;
    _finishing = true;
    _timer?.cancel();
    _stopListening();
    if (!mounted) return;
    final skippedMicrophone = _error != null;
    setState(() {
      _analyzing = true;
      _silent = false;
    });
    if (!skippedMicrophone && !_isWebSimulator) _announce('Checking the recording');

    ScreeningResult result;
    try {
      if (_isWebSimulator) {
        result = _screening.simulate(forceRed: forceRed);
        // Brief pause so the breath pulse is visible in the web demo.
        await Future<void>.delayed(const Duration(milliseconds: 700));
      } else if (_error != null || !_recording) {
        result = unavailableResult(
          reason: 'Microphone unavailable — use clinical judgment',
        );
      } else {
        result = await _screening.stopAndClassify();
      }
    } catch (_) {
      result = unavailableResult();
    }

    if (!mounted) {
      unawaited(_screening.dispose());
      return;
    }
    setState(() {
      _analyzing = false;
      _recording = false;
    });
    // Skip to vitals goes straight there; otherwise the result step, if it is on.
    if (_resultStep && !skippedMicrophone && !_isWebSimulator) {
      setState(() => _result = result);
      return;
    }
    await _toVitals(result);
  }

  Future<void> _toVitals(ScreeningResult result) => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VitalsScreen(result: result)),
      );

  /// Stops the model; [_finish] then carries on to vitals with the cancelled result.
  void _cancelAnalysis() {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _screening.cancelAnalysis();
  }

  Future<void> _openSettings() async {
    try {
      await AppSettings.openAppSettings();
    } catch (_) {
      // No settings page on this platform: Skip to vitals is still there.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopListening();
    _level.dispose();
    _finishing = true;
    // Leaving mid-analysis: stop the model rather than let it run on unseen.
    if (_analyzing) _screening.cancelAnalysis();
    // Do not dispose the recorder while classify may still be running;
    // stopAndClassify owns stop(); only dispose if we never started finish.
    if (!_analyzing) {
      unawaited(_screening.dispose());
    }
    super.dispose();
  }

  String get _title {
    if (_result != null) return 'Breathing check result';
    if (_error != null) return 'Permission needed';
    return 'Check breathing';
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_isWebSimulator) {
      body = _buildWebSimulator();
    } else if (_result != null) {
      body = _buildResult(_result!);
    } else if (_ready) {
      body = _buildReady();
    } else if (_analyzing) {
      body = _buildAnalysing();
    } else if (_error != null) {
      body = _buildBlocked();
    } else {
      body = _buildRecording();
    }
    final recording =
        !_isWebSimulator && _result == null && !_ready && !_analyzing && _error == null;
    final scaffold = Scaffold(
      // The recording frames have no title bar; system back still leaves (and stops).
      appBar: recording
          ? null
          : AppBar(title: Text(_permissionError || _error == null ? _title : 'Check breathing')),
      body: SafeArea(child: body),
    );
    // Without a title bar, keep the status bar on the page colour with dark icons.
    return recording
        ? AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: YomaColors.canvas),
            child: scaffold,
          )
        : scaffold;
  }

  /// A screen body that scrolls when it has to (large text, short screen) and centres
  /// its content otherwise, with the buttons pinned at the bottom.
  Widget _layout({required Widget content, required List<Widget> actions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: actions,
          ),
        ),
      ],
    );
  }

  Widget _buildReady() {
    final text = Theme.of(context).textTheme;
    const steps = [
      'Hold the phone close to the chest',
      'Keep the room quiet',
    ];
    return _layout(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const ChestPhoneIllustration(),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: YomaColors.surface,
              borderRadius: BorderRadius.circular(YomaRadii.lg),
              border: Border.all(color: YomaColors.grey200),
              boxShadow: YomaShadows.sm,
            ),
            child: Column(
              children: [
                for (final (i, step) in [
                  ...steps,
                  'Keep the phone still for $_total seconds',
                ].indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _NumberedStep(number: i + 1, text: step),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This is advice only. Always use your own judgement.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: YomaColors.grey600),
          ),
          const SizedBox(height: 16),
        ],
      ),
      actions: [
        FilledButton(
          key: const Key('screening_start'),
          onPressed: _start,
          child: const Text('Start'),
        ),
      ],
    );
  }

  /// As in the pulse frames: the LISTENING pill at the top, the pulse and two lines in
  /// the middle, the outlined Stop at the bottom. No title bar while recording.
  Widget _buildRecording() {
    final text = Theme.of(context).textTheme;
    final starting = !_recording;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: YomaColors.containerLow,
        borderRadius: BorderRadius.circular(YomaRadii.pill),
        border: Border.all(color: YomaColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text(
        starting ? 'STARTING' : 'LISTENING',
        style: text.labelSmall?.copyWith(color: YomaColors.primary, letterSpacing: 1.8),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Center(child: pill),
        ),
        Expanded(
          child: _layout(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: '${countOf(_remaining, 'second')} remaining',
                  excludeSemantics: true,
                  child: SizedBox(
                    height: RecordingPulse.box,
                    child: Center(
                      child: RecordingPulse(
                        remaining: _remaining,
                        total: _total,
                        level: _level,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  starting ? 'Starting microphone…' : 'Listening… keep the phone still',
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    color: YomaColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Do not speak or move until complete',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: YomaColors.grey600),
                ),
                if (_silent) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const Key('screening_silence_hint'),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: YomaColors.grey100,
                        borderRadius: BorderRadius.circular(YomaRadii.md),
                        border: Border.all(color: YomaColors.grey200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.hearing_disabled_outlined,
                              size: 18, color: YomaColors.grey700),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              silenceHintText,
                              style: text.bodyMedium?.copyWith(
                                color: YomaColors.grey800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              OutlinedButton(
                key: const Key('screening_stop'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => _finish(forceRed: false),
                child: const Text('Stop'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalysing() {
    final text = Theme.of(context).textTheme;
    return _layout(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              key: Key('screening_progress'),
              strokeWidth: 4,
              color: YomaColors.brand,
              backgroundColor: YomaColors.brandTint,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _cancelling ? 'Cancelling…' : 'Checking the recording…',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: YomaColors.navy, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'You can keep using the phone.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: YomaColors.grey600),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('screening_cancel'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _cancelling ? null : _cancelAnalysis,
          child: Text(_cancelling ? 'Cancelling…' : 'Cancel'),
        ),
      ],
    );
  }

  Widget _buildBlocked() {
    final text = Theme.of(context).textTheme;
    return _layout(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: YomaColors.navy.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(YomaRadii.lg),
              border: Border.all(color: YomaColors.grey200),
            ),
            child: const Icon(Icons.mic_off_outlined, size: 32, color: YomaColors.navy),
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            child: Text(
              _permissionError ? 'Microphone not allowed' : 'The microphone could not start',
              key: const Key('screening_mic_blocked'),
              textAlign: TextAlign.center,
              style:
                  text.titleMedium?.copyWith(color: YomaColors.navy, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _permissionError
                ? 'Allow the microphone in settings to check breathing, or skip this step'
                : 'Skip this step and record vitals, or try again later',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: YomaColors.grey600),
          ),
        ],
      ),
      actions: [
        if (_permissionError) ...[
          FilledButton(
            key: const Key('screening_open_settings'),
            onPressed: _openSettings,
            child: const Text('Open settings'),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(
          key: const Key('screening_skip_to_vitals'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => _finish(forceRed: false),
          child: const Text('Skip to vitals'),
        ),
      ],
    );
  }

  Widget _buildResult(ScreeningResult result) {
    final text = Theme.of(context).textTheme;
    return _layout(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BreathingResultCard(variant: BreathingVariant.of(result)),
          const SizedBox(height: 12),
          Text(
            'This is advice only. Always use your own judgement.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: YomaColors.grey600),
          ),
        ],
      ),
      actions: [
        FilledButton(
          key: const Key('screening_continue_to_vitals'),
          onPressed: () => _toVitals(result),
          child: const Text('Continue to vitals'),
        ),
      ],
    );
  }

  Widget _buildWebSimulator() {
    final text = Theme.of(context).textTheme;
    if (!demoClassifiersEnabled) {
      return _layout(
        content: Text(
          'Breathing screening is not available on web.',
          textAlign: TextAlign.center,
          style: text.titleLarge,
        ),
        actions: [
          FilledButton(
            onPressed: _analyzing ? null : () => _finish(forceRed: false),
            child: const Text('Continue to vitals'),
          ),
        ],
      );
    }
    return _layout(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Web demo simulator', style: text.titleLarge),
          const SizedBox(height: 8),
          Text(
            'On Android and iOS, YAMNet uses the microphone. '
            'On web, use these buttons to simulate screening.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: YomaColors.grey700),
          ),
          if (_analyzing) ...[
            const SizedBox(height: 24),
            BreathingPulse(
              active: true,
              child: Text('Checking…', style: text.titleLarge?.copyWith(color: YomaColors.brand)),
            ),
          ],
        ],
      ),
      // Demo only; neutral styling, no triage colours on breathing screens.
      actions: [
        OutlinedButton(
          onPressed: _analyzing ? null : () => _finish(forceRed: false),
          child: Text(_analyzing ? 'Checking…' : 'Demo Normal'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _analyzing ? null : () => _finish(forceRed: true),
          child: Text(_analyzing ? 'Checking…' : 'Demo Code Red'),
        ),
      ],
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Semantics(
      label: 'Step $number: $text',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: YomaColors.brandTint,
              border: Border.all(color: YomaColors.brand.withValues(alpha: 0.2)),
            ),
            child: Text('$number', style: theme.labelSmall?.copyWith(color: YomaColors.brand)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.labelMedium?.copyWith(color: YomaColors.grey800),
            ),
          ),
        ],
      ),
    );
  }
}
