import 'package:flutter/material.dart';

import '../theme/yoma_theme.dart';

/// The ambulance outline from the Stitch Home design (a Lucide icon, ISC licence), drawn
/// on its 24×24 grid. Material Icons has no ambulance glyph.
class AmbulanceIcon extends StatelessWidget {
  const AmbulanceIcon({super.key, this.size = 24, this.color, this.semanticLabel});

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      size: Size.square(size),
      painter: _AmbulancePainter(color ?? IconTheme.of(context).color ?? YomaColors.neutral),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semanticLabel, image: true, child: paint);
  }
}

class _AmbulancePainter extends CustomPainter {
  const _AmbulancePainter(this.color);

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
    const r = Radius.circular(2);

    // M10 17h4
    canvas.drawLine(const Offset(10, 17), const Offset(14, 17), paint);

    // Body: M19 17h1 a2 2 0 0 0 2-2 v-3 a2 2 0 0 0-.6-1.4 l-2.8-2.8 A2 2 0 0 0 17.2 7
    //       H15 V5 a2 2 0 0 0-2-2 H4 a2 2 0 0 0-2 2 v10 a2 2 0 0 0 2 2 h2
    final body = Path()
      ..moveTo(19, 17)
      ..lineTo(20, 17)
      ..arcToPoint(const Offset(22, 15), radius: r, clockwise: false)
      ..lineTo(22, 12)
      ..arcToPoint(const Offset(21.4, 10.6), radius: r, clockwise: false)
      ..lineTo(18.6, 7.8)
      ..arcToPoint(const Offset(17.2, 7), radius: r, clockwise: false)
      ..lineTo(15, 7)
      ..lineTo(15, 5)
      ..arcToPoint(const Offset(13, 3), radius: r, clockwise: false)
      ..lineTo(4, 3)
      ..arcToPoint(const Offset(2, 5), radius: r, clockwise: false)
      ..lineTo(2, 15)
      ..arcToPoint(const Offset(4, 17), radius: r, clockwise: false)
      ..lineTo(6, 17);
    canvas.drawPath(body, paint);

    // Wheels.
    canvas.drawCircle(const Offset(8, 17), 2, paint);
    canvas.drawCircle(const Offset(17, 17), 2, paint);

    // Cross: M8 7v4, M6 9h4.
    canvas.drawLine(const Offset(8, 7), const Offset(8, 11), paint);
    canvas.drawLine(const Offset(6, 9), const Offset(10, 9), paint);
  }

  @override
  bool shouldRepaint(_AmbulancePainter old) => old.color != color;
}
