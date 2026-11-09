import 'package:flutter/material.dart';

import '../theme/yoma_theme.dart';

/// The heart-pulse outline from the Stitch Home design (a Lucide icon, ISC licence), drawn
/// on its 24×24 grid. Material Icons has no heart with a pulse line.
class HeartPulseIcon extends StatelessWidget {
  const HeartPulseIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _HeartPulsePainter(color ?? IconTheme.of(context).color ?? YomaColors.neutral),
      ),
    );
  }
}

class _HeartPulsePainter extends CustomPainter {
  const _HeartPulsePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2
    // -1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z
    const r = Radius.circular(5.5);
    final heart = Path()
      ..moveTo(19, 14)
      ..cubicTo(20.49, 12.54, 22, 10.79, 22, 8.5)
      ..arcToPoint(const Offset(16.5, 3), radius: r, clockwise: false)
      ..cubicTo(14.74, 3, 13.5, 3.5, 12, 5)
      ..cubicTo(10.5, 3.5, 9.26, 3, 7.5, 3)
      ..arcToPoint(const Offset(2, 8.5), radius: r, clockwise: false)
      ..cubicTo(2, 10.8, 3.5, 12.55, 5, 14)
      ..lineTo(12, 21)
      ..close();
    canvas.drawPath(heart, paint);

    // M3.22 12H9.5l.5-1 2 4.5 2-7 1.5 3.5h5.27
    final pulse = Path()
      ..moveTo(3.22, 12)
      ..lineTo(9.5, 12)
      ..lineTo(10, 11)
      ..lineTo(12, 15.5)
      ..lineTo(14, 8.5)
      ..lineTo(15.5, 12)
      ..lineTo(20.77, 12);
    canvas.drawPath(pulse, paint);
  }

  @override
  bool shouldRepaint(_HeartPulsePainter old) => old.color != color;
}
