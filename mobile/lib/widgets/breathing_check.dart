import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import 'yoma_components.dart';

/// How the breathing check is shown. Never a "normal" or healthy-looking result: the
/// acoustic check can only raise a concern or say it couldn't tell.
enum BreathingVariant {
  possibleProblem(
    'Possible breathing problem',
    'Unusual breathing sounds were detected',
  ),
  couldntTell(
    "Couldn't tell",
    'Use your own judgement and record vitals',
  );

  const BreathingVariant(this.title, this.line);

  final String title;
  final String line;

  /// The app's existing mapping: only an acoustic RED raises a concern. Everything else
  /// (INCONCLUSIVE, cancelled, unavailable, and any GREEN) reads "Couldn't tell".
  static BreathingVariant of(ScreeningResult result) =>
      result.label.toUpperCase() == 'RED' ? possibleProblem : couldntTell;
}

/// Small grey "Advisory" tag.
class AdvisoryTag extends StatelessWidget {
  const AdvisoryTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: YomaColors.grey100,
        borderRadius: BorderRadius.circular(YomaRadii.sm - 2),
        border: Border.all(color: YomaColors.grey200),
      ),
      child: Text(
        'Advisory',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: YomaColors.grey700),
      ),
    );
  }
}

/// The breathing check result card: navy left border for a possible problem, grey
/// dashed border when it couldn't tell. No triage colours.
class BreathingResultCard extends StatelessWidget {
  const BreathingResultCard({super.key, required this.variant});

  final BreathingVariant variant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final problem = variant == BreathingVariant.possibleProblem;
    final ink = problem ? YomaColors.navy : YomaColors.grey800;
    final body = Padding(
      padding: EdgeInsets.fromLTRB(problem ? 14 : 14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: problem ? YomaColors.navy.withValues(alpha: 0.10) : YomaColors.grey100,
                ),
                child: Icon(
                  problem ? Icons.warning_amber_rounded : Icons.question_mark_rounded,
                  size: 18,
                  color: problem ? YomaColors.navy : YomaColors.grey600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(variant.title, style: text.titleMedium?.copyWith(color: ink)),
                ),
              ),
              if (problem) ...[const SizedBox(width: 8), const AdvisoryTag()],
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 38, top: 4),
            child: Text(variant.line, style: text.bodyMedium?.copyWith(color: YomaColors.grey600)),
          ),
        ],
      ),
    );

    final card = problem
        ? Container(
            decoration: BoxDecoration(
              color: YomaColors.surface,
              borderRadius: BorderRadius.circular(YomaRadii.md),
              border: Border.all(color: YomaColors.grey200),
              boxShadow: YomaShadows.sm,
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 6, color: YomaColors.navy),
                  Expanded(child: body),
                ],
              ),
            ),
          )
        : CustomPaint(
            painter: const DashedBorderPainter(color: YomaColors.grey500),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: YomaColors.surface,
                borderRadius: BorderRadius.circular(YomaRadii.md),
              ),
              child: body,
            ),
          );

    return Semantics(
      key: Key('breathing_result_${variant.name}'),
      container: true,
      liveRegion: true,
      label: 'Breathing check: ${variant.title}. ${variant.line}.'
          '${problem ? ' Advisory.' : ''}',
      excludeSemantics: true,
      child: card,
    );
  }
}

/// The recording circle, as in the pulse frames: a solid primary circle (138 dp) with the
/// countdown and "REMAINING", a 4 dp arc just outside it showing the time remaining, and
/// thin rings expanding and fading outward. The rings' reach follows the live microphone
/// [level]. With animations off (reduced motion) the rings are one static ring.
///
/// Only the ring painter repaints each frame (its own repaint boundary); no widget
/// rebuilds per frame.
class RecordingPulse extends StatefulWidget {
  const RecordingPulse({
    super.key,
    required this.remaining,
    required this.total,
    required this.level,
  });

  final int remaining;
  final int total;

  /// 0 (silent) to 1 (loud), already smoothed.
  final ValueNotifier<double> level;

  /// The frames' sizes, at their 224 dp box.
  static const box = 224.0;
  static const circle = 138.0;
  static const arcRadius = 74.0;

  @override
  State<RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<RecordingPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _phase.stop();
    } else if (!_phase.isAnimating) {
      _phase.repeat();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final remaining = widget.total <= 0 ? 0.0 : (widget.remaining / widget.total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The frames' 224 dp where it fits; scaled down as a whole on a short screen.
        final d = math.min(
          RecordingPulse.box,
          math.min(
            constraints.maxWidth,
            constraints.maxHeight.isFinite ? constraints.maxHeight : RecordingPulse.box,
          ),
        );
        final scale = d / RecordingPulse.box;
        final circle = RecordingPulse.circle * scale;
        return SizedBox(
          key: const Key('breathing_pulse'),
          width: d,
          height: d,
          child: Stack(
            alignment: Alignment.center,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  key: Key(_reduceMotion ? 'breathing_pulse_static' : 'breathing_pulse_rings'),
                  size: Size.square(d),
                  painter: _PulsePainter(
                    phase: _phase,
                    level: widget.level,
                    animate: !_reduceMotion,
                    scale: scale,
                    remaining: remaining,
                  ),
                ),
              ),
              Container(
                width: circle,
                height: circle,
                decoration: const BoxDecoration(
                  color: YomaColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: YomaShadows.md,
                ),
                child: ExcludeSemantics(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${widget.remaining} s',
                            key: const Key('screening_countdown'),
                            style: text.headlineMedium?.copyWith(
                              color: YomaColors.onPrimary,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'REMAINING',
                            style: text.labelSmall?.copyWith(
                              color: YomaColors.onPrimary.withValues(alpha: 0.85),
                              letterSpacing: 1.5,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.phase,
    required this.level,
    required this.animate,
    required this.scale,
    required this.remaining,
  }) : super(repaint: animate ? Listenable.merge([phase, level]) : level);

  final Animation<double> phase;
  final ValueNotifier<double> level;
  final bool animate;
  final double scale;
  final double remaining;

  /// As in the frames: three thin rings, at most two or three visible at once.
  static const _rings = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final arcR = RecordingPulse.arcRadius * scale;
    final firstRing = 84 * scale; // the frames' innermost ring (168 dp)
    final outer = size.width / 2 - 1; // the frames' outermost (224 dp)
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (animate) {
      // Quiet: the rings stay close. Louder: they travel out to the edge.
      final reach = (outer - firstRing) * (0.35 + 0.65 * level.value.clamp(0.0, 1.0));
      for (var i = 0; i < _rings; i++) {
        final t = (phase.value + i / _rings) % 1.0;
        // 40% opacity at the circle, fading to 8% at the edge, as in the frames.
        ring.color = YomaColors.tertiary.withValues(alpha: 0.40 - 0.32 * t);
        canvas.drawCircle(c, firstRing + reach * t, ring);
      }
    } else {
      ring.color = YomaColors.tertiary.withValues(alpha: 0.30);
      canvas.drawCircle(c, firstRing + (outer - firstRing) * 0.35, ring);
    }

    // Time remaining, just outside the solid circle (the frames' arc, from the top).
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = YomaColors.line;
    canvas.drawCircle(c, arcR, track);
    if (remaining > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = YomaColors.primary;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: arcR),
        -math.pi / 2,
        2 * math.pi * remaining,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.remaining != remaining ||
      old.animate != animate ||
      old.scale != scale ||
      old.level != level;
}

/// The Ready screen's line drawing: a person holding a phone to the chest (from the
/// Stitch design's SVG, on its 24×24 grid).
class ChestPhoneIllustration extends StatelessWidget {
  const ChestPhoneIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: YomaColors.brandTint,
        borderRadius: BorderRadius.circular(YomaRadii.lg),
        border: Border.all(color: YomaColors.grey200),
      ),
      alignment: Alignment.center,
      child: const ExcludeSemantics(
        child: CustomPaint(size: Size.square(48), painter: _ChestPhonePainter()),
      ),
    );
  }
}

class _ChestPhonePainter extends CustomPainter {
  const _ChestPhonePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = YomaColors.brand
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const r5 = Radius.circular(5);
    // Shoulders: M4 20v-2a5 5 0 015-5h1  and  m6 7v-2a5 5 0 00-3-4.6
    canvas.drawPath(
      Path()
        ..moveTo(4, 20)
        ..lineTo(4, 18)
        ..arcToPoint(const Offset(9, 13), radius: r5)
        ..lineTo(10, 13),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(16, 20)
        ..lineTo(16, 18)
        ..arcToPoint(const Offset(13, 13.4), radius: r5, clockwise: false),
      stroke,
    );
    canvas.drawCircle(const Offset(9, 7), 3, stroke);
    final phone =
        RRect.fromRectAndRadius(const Rect.fromLTWH(14, 9, 7, 11), const Radius.circular(1.5));
    canvas.drawRRect(phone, Paint()..color = YomaColors.onPrimary);
    canvas.drawRRect(phone, stroke);
    canvas.drawLine(const Offset(17.5, 12), const Offset(17.5, 15), stroke);
    canvas.drawLine(const Offset(16, 13.5), const Offset(19, 13.5), stroke);
  }

  @override
  bool shouldRepaint(_ChestPhonePainter old) => false;
}
