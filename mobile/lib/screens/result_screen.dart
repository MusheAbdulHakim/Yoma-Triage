import 'package:flutter/material.dart';

import '../services/moews_calculator.dart';
import '../services/moews_explanation.dart';
import '../services/referral_gating.dart';
import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import '../widgets/breathing_check.dart';
import '../widgets/yoma_components.dart';
import 'referral_screen.dart';

class ResultScreen extends StatelessWidget {
  final ScreeningResult result;
  final MoewsResult? moews;
  final Map<String, Object?>? vitals;

  const ResultScreen({
    super.key,
    required this.result,
    this.moews,
    this.vitals,
  });

  bool get _acousticDisabled => result.source == 'moews_only';

  bool get _isDemoSource =>
      result.source == 'stub' || result.source == 'simulator';

  void _openReferral(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReferralScreen(
          aiScreenResult: result.label,
          aiConfidence: result.confidence,
          aiModelVersion: result.modelVersion,
          initialVitals: vitals,
        ),
      ),
    );
  }

  void _backHome(BuildContext context) =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final indicate = referralIndicated(
      acousticLabel: result.label,
      moewsRiskLevel: moews?.riskLevel,
    );
    final m = moews;
    final level = TriageLevel.fromMoews(m?.riskLevel);

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  YomaSpacing.gutter, YomaSpacing.md, YomaSpacing.gutter, YomaSpacing.lg),
              children: [
                _Disclaimer(demo: _isDemoSource),
                const SizedBox(height: YomaSpacing.md),
                if (m != null && level != null) ...[
                  _RiskCard(moews: m, level: level),
                  const SizedBox(height: YomaSpacing.xl),
                  ..._details(context, m, level),
                ] else
                  BreathingResultCard(variant: BreathingVariant.of(result)),
                if (m != null && !_acousticDisabled) ...[
                  const SizedBox(height: YomaSpacing.lg),
                  _BreathingAdvisoryRow(variant: BreathingVariant.of(result)),
                  if (m.hrAbnormal)
                    Padding(
                      padding: const EdgeInsets.only(top: YomaSpacing.sm),
                      child: Text(
                        'Heart rate contributes MOEWS ${m.hrScore} '
                        '(abnormal band — escalate attention).',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: YomaColors.grey800,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          _Actions(
            indicate: indicate,
            onConfirm: () => _openReferral(context),
            onMonitor: () => _backHome(context),
          ),
        ],
      ),
    );
  }

  /// "Why" for a scored result; "Not measured" for an incomplete one.
  List<Widget> _details(BuildContext context, MoewsResult m, TriageLevel level) {
    final text = Theme.of(context).textTheme;
    final why = explainMoews(m, vitals ?? const {});
    final missing = m.missingVitals;
    final onlySpo2Missing = missing.length == 1 && missing.first == 'spo2';
    final dot = level == TriageLevel.amber ? const Color(0xFFD97706) : level.colour;

    return [
      if (why.isNotEmpty) ...[
        const _SectionTitle('Why'),
        for (final row in why)
          _DotRow(
            text: row.text,
            colour: dot,
            filled: row.critical,
            semanticPrefix: row.critical ? 'Critical' : 'Borderline',
          ),
        const SizedBox(height: YomaSpacing.lg),
      ] else if (level == TriageLevel.green) ...[
        const _SectionTitle('Why'),
        Text(
          'Every measured vital is in the normal range.',
          style: text.bodyLarge?.copyWith(color: YomaColors.grey800),
        ),
        const SizedBox(height: YomaSpacing.lg),
      ],
      if (m.isIncomplete) ...[
        Semantics(
          container: true,
          key: const Key('moews_not_measured'),
          label: m.notMeasuredText,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('Not measured'),
              for (final name in missing)
                _DotRow(
                  text: vitalDisplayNames[name] ?? name,
                  colour: TriageColors.incompleteBorder,
                  filled: true,
                ),
            ],
          ),
        ),
      ] else if (missing.isNotEmpty)
        Text(
          onlySpo2Missing
              ? 'Oxygen saturation not measured'
              : 'Not measured: ${missing.map((n) => vitalDisplayNames[n] ?? n).join(', ')}',
          key: const Key('moews_not_measured'),
          style: text.bodyMedium?.copyWith(color: YomaColors.grey600),
        ),
    ];
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.demo});

  final bool demo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline, size: 18, color: YomaColors.grey600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Advisory only — not a diagnosis. Not clinically validated.',
                style: text.bodyMedium?.copyWith(
                  color: YomaColors.grey700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (demo)
                Text(
                  'Demo screening mode.',
                  style: text.bodySmall?.copyWith(color: YomaColors.grey700),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The large risk card. Coloured by level, named in words, and announced as such.
class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.moews, required this.level});

  final MoewsResult moews;
  final TriageLevel level;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final incomplete = level == TriageLevel.incomplete;
    final partial = moews.missingVitals.any((name) => name != 'spo2');
    final score = moews.score;
    final detail = incomplete
        ? 'Cannot call this patient normal without a full set of vitals'
        : [
            if (score != null) 'Score $score',
            if (partial) 'from measured vitals',
          ].join(' · ');

    final content = Padding(
      padding: const EdgeInsets.all(YomaSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: incomplete
                  ? YomaColors.grey200
                  : level == TriageLevel.amber
                      ? Colors.black.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(YomaRadii.sm),
            ),
            child: Icon(level.icon, size: 30, color: level.onColour),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  incomplete ? 'Incomplete' : level.word,
                  style: text.headlineSmall?.copyWith(color: level.onColour),
                ),
                const SizedBox(height: 2),
                Text(level.moewsName, style: text.labelLarge?.copyWith(color: level.onColour)),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: (incomplete ? text.bodyMedium : text.labelLarge)
                        ?.copyWith(color: level.onColour),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      key: const Key('result_risk_card'),
      container: true,
      label: 'Risk level: ${level.word}. ${level.moewsName}. $detail',
      excludeSemantics: true,
      child: incomplete
          ? CustomPaint(
              painter: const DashedBorderPainter(color: TriageColors.incompleteBorder),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: level.colour,
                  borderRadius: BorderRadius.circular(YomaRadii.md),
                ),
                child: content,
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                color: level.colour,
                borderRadius: BorderRadius.circular(YomaRadii.md),
                boxShadow: YomaShadows.md,
              ),
              child: content,
            ),
    );
  }
}

/// The breathing check on the Result screen: one small secondary row with the variant in
/// an outlined badge. Dark grey, no triage colours, no score.
class _BreathingAdvisoryRow extends StatelessWidget {
  const _BreathingAdvisoryRow({required this.variant});

  final BreathingVariant variant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('result_breathing_advisory'),
      container: true,
      label: 'Breathing check, advisory: ${variant.title}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: YomaColors.surface,
          borderRadius: BorderRadius.circular(YomaRadii.md),
          border: Border.all(color: YomaColors.grey200),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.graphic_eq, size: 18, color: YomaColors.grey700),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Breathing check (advisory)',
                    style: text.labelMedium?.copyWith(color: YomaColors.grey800),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(YomaRadii.pill),
                border: Border.all(color: YomaColors.grey600),
              ),
              child: Text(
                variant.title,
                style: text.labelSmall?.copyWith(color: YomaColors.grey800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: YomaSpacing.md),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// A list row with a dot: filled for critical, outlined for borderline.
class _DotRow extends StatelessWidget {
  const _DotRow({
    required this.text,
    required this.colour,
    required this.filled,
    this.semanticPrefix,
  });

  final String text;
  final Color colour;
  final bool filled;
  final String? semanticPrefix;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticPrefix == null ? text : '$semanticPrefix: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? colour : Colors.transparent,
                  border: filled ? null : Border.all(color: colour, width: 2),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: YomaColors.grey800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom actions. Referral is always the CHO's call: no score removes that option.
class _Actions extends StatelessWidget {
  const _Actions({required this.indicate, required this.onConfirm, required this.onMonitor});

  final bool indicate;
  final VoidCallback onConfirm;
  final VoidCallback onMonitor;

  @override
  Widget build(BuildContext context) {
    final primary = FilledButton(
      key: const Key('result_primary'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(YomaSizes.primaryButton)),
      onPressed: indicate ? onConfirm : onMonitor,
      child: Text(indicate ? 'Confirm Referral' : 'Continue Monitoring'),
    );
    final secondary = OutlinedButton(
      key: const Key('result_secondary'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(YomaSizes.minTap)),
      onPressed: indicate ? onMonitor : onConfirm,
      child: Text(indicate ? 'Continue Monitoring' : 'Refer with clinical judgment'),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: YomaColors.surface,
        border: Border(top: BorderSide(color: YomaColors.grey100)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              YomaSpacing.gutter, YomaSpacing.md, YomaSpacing.gutter, YomaSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 10), secondary],
          ),
        ),
      ),
    );
  }
}
