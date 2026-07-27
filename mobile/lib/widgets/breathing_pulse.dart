import 'package:flutter/material.dart';

import '../theme/yoma_theme.dart';

/// Concentric calm breath rings around [child] while [active] is true.
///
/// Stops immediately when [active] becomes false (e.g. screening result ready).
class BreathingPulse extends StatefulWidget {
  final bool active;
  final Widget child;
  final Color color;
  final double size;

  const BreathingPulse({
    super.key,
    required this.active,
    required this.child,
    this.color = YomaColors.brand,
    this.size = 220,
  });

  @override
  State<BreathingPulse> createState() => _BreathingPulseState();
}

class _BreathingPulseState extends State<BreathingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.active) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BreathingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('breathing_pulse'),
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.active)
            AnimatedBuilder(
              key: const Key('breathing_pulse_rings'),
              animation: _controller,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_controller.value);
                return CustomPaint(
                  size: Size.square(widget.size),
                  painter: _BreathRingsPainter(
                    progress: t,
                    color: widget.color,
                  ),
                );
              },
            ),
          widget.child,
        ],
      ),
    );
  }
}

class _BreathRingsPainter extends CustomPainter {
  final double progress;
  final Color color;

  _BreathRingsPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;

    for (var i = 0; i < 3; i++) {
      final lag = i * 0.18;
      final local = ((progress + lag) % 1.0);
      final radius = maxRadius * (0.42 + local * 0.55);
      final opacity = (1.0 - local) * (0.38 - i * 0.08);
      if (opacity <= 0) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 - i * 0.6
        ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawCircle(center, radius, paint);
    }

    // Soft filled core so the countdown sits on a calm disc.
    final core = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.08 + progress * 0.06);
    canvas.drawCircle(center, maxRadius * (0.34 + progress * 0.04), core);
  }

  @override
  bool shouldRepaint(covariant _BreathRingsPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
