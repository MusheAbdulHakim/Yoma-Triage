import 'package:flutter/material.dart';

import '../services/dispatch_timeline.dart';
import '../services/friendly_time.dart';
import '../theme/yoma_theme.dart';

/// The vertical dispatch timeline. Done: filled teal circle with a check. Current: teal
/// ring with a dot. Future: grey outline. No triage colours.
class DispatchTimelineView extends StatelessWidget {
  const DispatchTimelineView({super.key, required this.steps});

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, step) in steps.indexed) _StepRow(step: step, isLast: i == steps.length - 1),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isLast});

  final TimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final labelColour = switch (step.state) {
      TimelineState.done => YomaColors.grey900,
      // The current step stands out from the navy done steps (the design's coloured label).
      TimelineState.current => YomaColors.tertiary,
      TimelineState.future => YomaColors.grey600,
    };
    final time = step.at == null ? null : shortWhen(context, step.at!);
    return Semantics(
      key: Key('timeline_${step.id}_${step.state.name}'),
      container: true,
      liveRegion: step.state == TimelineState.current,
      label: step.spokenWith(time),
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  _Dot(state: step.state),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: step.state == TimelineState.done
                            ? YomaColors.brand.withValues(alpha: 0.5)
                            : YomaColors.grey200,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            step.label,
                            style: text.titleMedium?.copyWith(
                              color: labelColour,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (time != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 2),
                            child: Text(
                              time,
                              key: Key('timeline_${step.id}_time'),
                              style: text.bodySmall?.copyWith(color: YomaColors.grey700),
                            ),
                          ),
                      ],
                    ),
                    // Who is coming, in a small bordered card as in the design.
                    if (step.detail != null)
                      Container(
                        key: Key('timeline_${step.id}_detail'),
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: YomaColors.surface,
                          borderRadius: BorderRadius.circular(YomaRadii.sm),
                          border: Border.all(color: YomaColors.line),
                        ),
                        child: Text(
                          step.detail!,
                          style: text.labelMedium?.copyWith(color: YomaColors.grey900),
                        ),
                      ),
                    if (step.note != null)
                      Container(
                        key: const Key('timeline_note'),
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: YomaColors.brandTint,
                          borderRadius: BorderRadius.circular(YomaRadii.sm),
                          border: Border.all(color: YomaColors.brand.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          step.note!,
                          style: text.bodyMedium?.copyWith(
                            color: YomaColors.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final TimelineState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      TimelineState.done => Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(color: YomaColors.brand, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, size: 15, color: YomaColors.onPrimary),
        ),
      TimelineState.current => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: YomaColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: YomaColors.brand, width: 2.5),
            // The design's soft halo around the current step.
            boxShadow: [
              BoxShadow(color: YomaColors.tertiary.withValues(alpha: 0.25), spreadRadius: 4),
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(color: YomaColors.brand, shape: BoxShape.circle),
          ),
        ),
      TimelineState.future => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: YomaColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: YomaColors.grey500, width: 2),
          ),
        ),
    };
  }
}

/// The dark navy card over the Call/SMS rows when the CHO should reach someone
/// themselves.
class NavyHelpCard extends StatelessWidget {
  const NavyHelpCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: YomaColors.navy,
          borderRadius: BorderRadius.circular(YomaRadii.md),
          boxShadow: YomaShadows.md,
        ),
        child: Row(
          children: [
            // White, not amber: no triage colours on this screen.
            const Icon(Icons.warning_amber_rounded, color: YomaColors.onPrimary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: YomaColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
