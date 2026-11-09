import 'package:flutter/material.dart';

import '../theme/yoma_theme.dart';

/// How a MOEWS risk level looks and reads. Colour is never the only signal: every level
/// has its own word and icon, and the word is what a screen reader announces.
enum TriageLevel {
  red('Critical', 'MOEWS RED', TriageColors.red, TriageColors.onRed, Icons.warning_amber_rounded),
  amber('Elevated', 'MOEWS YELLOW', TriageColors.amber, TriageColors.onAmber, Icons.schedule),
  green('Stable', 'MOEWS GREEN', TriageColors.green, TriageColors.onGreen, Icons.check_rounded),
  incomplete('Incomplete', 'MOEWS INCOMPLETE', TriageColors.incompleteFill,
      TriageColors.onIncomplete, Icons.question_mark_rounded);

  const TriageLevel(this.word, this.moewsName, this.colour, this.onColour, this.icon);

  /// The plain word shown as the headline.
  final String word;

  /// The MOEWS name the app has always shown; kept next to the word.
  final String moewsName;
  final Color colour;
  final Color onColour;
  final IconData icon;

  /// From the calculator's `riskLevel` (RED / YELLOW / GREEN / INCOMPLETE).
  static TriageLevel? fromMoews(String? riskLevel) => switch (riskLevel?.toUpperCase()) {
        'RED' => red,
        'YELLOW' => amber,
        'GREEN' => green,
        'INCOMPLETE' => incomplete,
        _ => null,
      };
}

/// White card with a hairline border, as in every redesigned screen.
class YomaCard extends StatelessWidget {
  const YomaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(YomaSpacing.lg),
    this.color = YomaColors.surface,
    this.borderColor = YomaColors.grey200,
    this.borderWidth = 1,
    this.radius = YomaRadii.lg,
    this.shadow = YomaShadows.sm,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final double radius;
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: shadow,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A large single-choice tap target (consciousness level, emergency type).
class YomaChoiceChip extends StatelessWidget {
  const YomaChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticsHint,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelMedium!;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      hint: semanticsHint,
      child: Material(
        color: selected ? YomaColors.secondary : YomaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YomaRadii.md),
          side: BorderSide(
            color: selected ? YomaColors.secondary : YomaColors.grey300,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(YomaRadii.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: YomaSizes.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: text.copyWith(
                    color: selected ? YomaColors.onPrimary : YomaColors.grey800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The slim strip at the bottom of Home: light while things are waiting, dark navy when
/// something has failed.
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.title,
    required this.subtitle,
    required this.dark,
    required this.expanded,
    required this.onTap,
    this.stripKey,
  });

  final String title;
  final String subtitle;
  final bool dark;
  final bool expanded;
  final VoidCallback onTap;
  final Key? stripKey;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fg = dark ? YomaColors.onPrimary : YomaColors.grey800;
    final fgMuted = dark ? YomaColors.onDark : YomaColors.grey600;
    return Material(
      key: stripKey,
      color: dark ? YomaColors.navy : YomaColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YomaRadii.md),
        side: dark ? BorderSide.none : const BorderSide(color: YomaColors.grey200),
      ),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(YomaRadii.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: YomaSizes.minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(
                  dark ? Icons.error_outline : Icons.info_outline,
                  size: 20,
                  color: fg,
                  semanticLabel: dark ? 'Failure' : 'Information',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: textTheme.labelMedium?.copyWith(color: fg),
                      ),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(color: fgMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 20,
                  color: fg,
                  semanticLabel: expanded ? 'Hide warnings' : 'Show warnings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the open warning list under the status strip.
class StatusStripItem extends StatelessWidget {
  const StatusStripItem({
    super.key,
    required this.urgent,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final bool urgent;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fg = urgent ? YomaColors.onPrimary : YomaColors.grey800;
    final fgMuted = urgent ? YomaColors.onDark : YomaColors.grey600;
    return Padding(
      padding: const EdgeInsets.only(top: YomaSpacing.sm),
      child: Material(
        color: urgent ? YomaColors.navy : YomaColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YomaRadii.md),
          side: urgent ? BorderSide.none : const BorderSide(color: YomaColors.grey200),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(YomaRadii.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: YomaSizes.minTap),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: textTheme.labelMedium?.copyWith(color: fg)),
                        if (subtitle != null)
                          Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: fgMuted)),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!
                  else if (onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 6),
                      child: Icon(Icons.chevron_right, size: 20, color: fg),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill naming a risk level, e.g. on the referral summary row.
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.level, this.score});

  final TriageLevel level;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final label = score == null ? level.word : '${level.word} (Score $score)';
    final incomplete = level == TriageLevel.incomplete;
    return Semantics(
      label: 'Risk level: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: level.colour,
          borderRadius: BorderRadius.circular(YomaRadii.pill),
          border: incomplete ? Border.all(color: TriageColors.incompleteBorder) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(level.icon, size: 14, color: level.onColour),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: level.onColour),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rectangle drawn with a dashed border, for the Incomplete result card.
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    this.radius = YomaRadii.md,
    this.strokeWidth = 2,
    this.dash = 6,
    this.gap = 4,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth;
}
