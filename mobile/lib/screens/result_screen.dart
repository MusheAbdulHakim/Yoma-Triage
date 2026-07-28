import 'package:flutter/material.dart';

import '../services/moews_calculator.dart';
import '../services/referral_gating.dart';
import '../services/screening_result.dart';
import '../theme/yoma_theme.dart';
import 'referral_screen.dart';

class ResultScreen extends StatelessWidget {
  final ScreeningResult result;
  final MoewsResult? moews;
  final Map<String, Object>? vitals;

  const ResultScreen({
    super.key,
    required this.result,
    this.moews,
    this.vitals,
  });

  Color _acousticColor(String label) {
    switch (label) {
      case 'RED':
        return YomaColors.danger;
      case 'GREEN':
        return YomaColors.safe;
      default:
        return YomaColors.caution;
    }
  }

  bool get _isDemoSource =>
      result.source == 'stub' || result.source == 'simulator';

  Color _moewsColor(MoewsResult m) {
    switch (m.riskLevel) {
      case 'RED':
        return YomaColors.danger;
      case 'YELLOW':
        return YomaColors.caution;
      case 'GREEN':
        return YomaColors.safe;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final indicate = referralIndicated(
      acousticLabel: result.label,
      moewsRiskLevel: moews?.riskLevel,
    );
    final heroIsMoews = moews != null;
    final heroColor =
        heroIsMoews ? _moewsColor(moews!) : _acousticColor(result.label);
    final heroTitle =
        heroIsMoews ? 'MOEWS ${moews!.riskLevel}' : result.label;
    final heroSubtitle = heroIsMoews
        ? 'Clinical spine'
            '${moews!.score != null ? ' · score ${moews!.score}' : ''}'
            '${moews!.hrAbnormal ? ' · HR band elevated' : ''}'
        : result.reason;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screening Result'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            color: YomaColors.caution.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Advisory only — not a diagnosis. Not clinically validated.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (_isDemoSource) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Demo screening mode.',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: heroColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: heroColor, width: 2),
            ),
            child: Column(
              children: [
                Text(
                  heroTitle,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: heroColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  heroSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
          if (moews != null) ...[
            const SizedBox(height: 16),
            Card(
              color: _acousticColor(result.label).withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Acoustic (advisory): ${result.label}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _acousticColor(result.label),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(result.reason),
                    const SizedBox(height: 4),
                    Text(
                      'Confidence: ${(result.confidence * 100).toStringAsFixed(0)}%'
                      ' · ${result.source}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    if (moews!.hrAbnormal) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Heart rate contributes MOEWS ${moews!.hrScore} '
                        '(abnormal band — escalate attention).',
                        style: const TextStyle(
                          color: YomaColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Confidence: ${(result.confidence * 100).toStringAsFixed(0)}%'
              ' · ${result.source}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 32),
          if (indicate)
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () {
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
              },
              child: const Text('Confirm Referral'),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Continue Monitoring'),
            ),
          if (result.label == 'INCONCLUSIVE') ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
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
              },
              child: const Text('Refer with clinical judgment'),
            ),
          ] else if (indicate) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Continue Monitoring'),
            ),
          ],
        ],
      ),
    );
  }
}
