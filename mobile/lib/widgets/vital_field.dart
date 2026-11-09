import 'package:flutter/material.dart';

import '../services/vital_limits.dart';
import '../theme/yoma_theme.dart';
import 'yoma_components.dart';

/// One vital sign: a typed value, or an explicit "not measured".
///
/// Fields start blank and a value is never assumed. "Not measured" is sent as
/// null, which the backend and on-device MOEWS treat as missing data.
class VitalInput {
  VitalInput();

  /// Restores a value recorded earlier in the session. A key holding null was
  /// marked not measured; a missing key has not been answered yet.
  VitalInput.fromVitals(Map<String, Object?>? vitals, String key) {
    if (vitals == null || !vitals.containsKey(key)) return;
    final value = vitals[key];
    if (value == null) {
      notMeasured = true;
    } else {
      controller.text = value.toString();
    }
  }

  final TextEditingController controller = TextEditingController();
  bool notMeasured = false;

  /// Typed a value, or marked not measured.
  bool get answered => notMeasured || controller.text.trim().isNotEmpty;

  int? get intValue => notMeasured ? null : int.tryParse(controller.text.trim());

  double? get doubleValue =>
      notMeasured ? null : double.tryParse(controller.text.trim());

  void setValue(Object value) {
    notMeasured = false;
    controller.text = value.toString();
  }

  void dispose() => controller.dispose();
}

/// The validation every vital field uses. Messages are unchanged from before the
/// redesign.
String? _validateVital(VitalInput input, VitalLimits limits, bool decimal, String? value) {
  if (input.notMeasured) return null;
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return 'Enter a value or tick Not measured';
  final parsed = decimal ? double.tryParse(raw) : int.tryParse(raw);
  if (parsed == null) {
    return decimal ? 'Invalid number' : 'Invalid whole number';
  }
  return limits.errorFor(parsed);
}

/// The "Not measured" / "Clear" toggle under a field. At least 48 dp to tap.
class _NotMeasuredToggle extends StatelessWidget {
  const _NotMeasuredToggle({
    required this.toggleKey,
    required this.notMeasured,
    required this.onTap,
    required this.label,
  });

  final Key toggleKey;
  final bool notMeasured;
  final VoidCallback onTap;

  /// What the toggle is for, for screen readers.
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: YomaColors.grey700,
          decoration: TextDecoration.underline,
          decorationColor: YomaColors.grey700,
        );
    return Semantics(
      button: true,
      toggled: notMeasured,
      label: notMeasured ? 'Clear: $label marked not measured' : '$label not measured',
      excludeSemantics: true,
      child: InkWell(
        key: toggleKey,
        borderRadius: BorderRadius.circular(YomaRadii.sm),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: YomaSizes.minTap,
            minWidth: YomaSizes.minTap,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(notMeasured ? 'Clear' : 'Not measured', style: style),
            ),
          ),
        ),
      ),
    );
  }
}

/// The text box for a vital value: big digits, unit inside, teal when focused.
class _VitalTextField extends StatelessWidget {
  const _VitalTextField({
    required this.fieldKey,
    required this.input,
    required this.limits,
    required this.decimal,
    required this.label,
    required this.unit,
    required this.highlight,
    required this.onChanged,
  });

  final String fieldKey;
  final VitalInput input;
  final VitalLimits limits;
  final bool decimal;
  final String label;
  final String? unit;
  final bool highlight;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final notMeasured = input.notMeasured;
    return TextFormField(
      key: Key(fieldKey),
      controller: input.controller,
      enabled: !notMeasured,
      textAlign: TextAlign.end,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      style: text.headlineSmall?.copyWith(fontSize: 20, height: 1.2),
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        // The visible label sits beside the field; this one names it for screen readers.
        semanticCounterText: '',
        hintText: notMeasured ? 'NOT MEASURED' : '—',
        hintStyle: notMeasured
            ? text.labelSmall?.copyWith(color: YomaColors.grey700, letterSpacing: 0.6)
            : text.headlineSmall?.copyWith(fontSize: 20, color: YomaColors.grey500),
        suffixText: notMeasured ? null : unit,
        suffixStyle: text.labelSmall?.copyWith(color: YomaColors.grey600),
        errorMaxLines: 3,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        fillColor: notMeasured
            ? YomaColors.grey200
            : highlight
                ? YomaColors.warning.withValues(alpha: 0.08)
                : YomaColors.canvas,
        enabledBorder: highlight
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(YomaRadii.md),
                borderSide: const BorderSide(color: YomaColors.warning, width: 1.5),
              )
            : null,
      ),
      validator: (value) => _validateVital(input, limits, decimal, value),
    );
  }
}

/// One vital sign in its own compact card: label left, value right, and a
/// "Not measured" toggle under the label.
class VitalField extends StatefulWidget {
  const VitalField({
    super.key,
    required this.input,
    required this.label,
    required this.fieldKey,
    required this.limits,
    this.unit,
    this.decimal = false,
    this.highlight = false,
    this.helperText,
    this.onChanged,
  });

  final VitalInput input;
  final String label;

  /// Key of the text field; the toggle is `<fieldKey>_not_measured`.
  final String fieldKey;
  final VitalLimits limits;
  final String? unit;
  final bool decimal;
  final bool highlight;
  final String? helperText;

  /// Called whenever the value or the not-measured state changes.
  final VoidCallback? onChanged;

  @override
  State<VitalField> createState() => _VitalFieldState();
}

class _VitalFieldState extends State<VitalField> {
  void _setNotMeasured(bool value) {
    setState(() {
      widget.input.notMeasured = value;
      if (value) widget.input.controller.clear();
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final notMeasured = widget.input.notMeasured;
    final label = Text(
      widget.label,
      style: text.titleMedium?.copyWith(
        color: notMeasured ? YomaColors.grey600 : YomaColors.grey800,
      ),
    );
    final toggle = _NotMeasuredToggle(
      toggleKey: Key('${widget.fieldKey}_not_measured'),
      notMeasured: notMeasured,
      label: widget.label,
      onTap: () => _setNotMeasured(!notMeasured),
    );
    Widget field(double width) => SizedBox(
          width: width,
          child: Semantics(
            label: widget.label,
            child: _VitalTextField(
              fieldKey: widget.fieldKey,
              input: widget.input,
              limits: widget.limits,
              decimal: widget.decimal,
              label: widget.label,
              unit: widget.unit,
              highlight: widget.highlight,
              onChanged: () => widget.onChanged?.call(),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: YomaSpacing.sm),
      child: YomaCard(
        color: notMeasured ? YomaColors.grey100 : YomaColors.surface,
        shadow: notMeasured ? const [] : YomaShadows.sm,
        padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // One row (label, toggle, value) where it fits, so most of the form shows on
            // 360×640. On a narrow screen or with large text, the toggle goes under the label.
            final oneRow = constraints.maxWidth >= 290 &&
                MediaQuery.textScalerOf(context).scale(16) <= 16 * 1.15;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (oneRow)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(child: label),
                        toggle,
                        const SizedBox(width: 6),
                        field(104),
                      ],
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [const SizedBox(height: 10), label, toggle],
                        ),
                      ),
                      const SizedBox(width: YomaSpacing.sm),
                      Padding(padding: const EdgeInsets.only(top: 6), child: field(120)),
                    ],
                  ),
                if (widget.helperText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      widget.helperText!,
                      style: text.bodySmall?.copyWith(
                        color: widget.highlight ? YomaColors.warning : YomaColors.grey600,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Systolic and diastolic in one card, each with its own field and toggle on a row under
/// the label. Each is still a separate vital, as before.
class BloodPressureField extends StatefulWidget {
  const BloodPressureField({
    super.key,
    required this.systolic,
    required this.diastolic,
    required this.systolicKey,
    required this.diastolicKey,
    this.onChanged,
  });

  final VitalInput systolic;
  final VitalInput diastolic;
  final String systolicKey;
  final String diastolicKey;
  final VoidCallback? onChanged;

  @override
  State<BloodPressureField> createState() => _BloodPressureFieldState();
}

class _BloodPressureFieldState extends State<BloodPressureField> {
  void _toggle(VitalInput input) {
    setState(() {
      input.notMeasured = !input.notMeasured;
      if (input.notMeasured) input.controller.clear();
    });
    widget.onChanged?.call();
  }

  Widget _half(String name, VitalInput input, String key, VitalLimits limits) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: text.bodySmall?.copyWith(color: YomaColors.grey600)),
        const SizedBox(height: 4),
        Semantics(
          label: '$name blood pressure',
          child: _VitalTextField(
            fieldKey: key,
            input: input,
            limits: limits,
            decimal: false,
            label: name,
            unit: 'mmHg',
            highlight: false,
            onChanged: () => widget.onChanged?.call(),
          ),
        ),
        _NotMeasuredToggle(
          toggleKey: Key('${key}_not_measured'),
          notMeasured: input.notMeasured,
          label: '$name blood pressure',
          onTap: () => _toggle(input),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final both = widget.systolic.notMeasured && widget.diastolic.notMeasured;
    return Padding(
      padding: const EdgeInsets.only(bottom: YomaSpacing.sm),
      child: YomaCard(
        color: both ? YomaColors.grey100 : YomaColors.surface,
        shadow: both ? const [] : YomaShadows.sm,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Blood pressure', style: text.titleMedium?.copyWith(color: YomaColors.grey800)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _half('Systolic', widget.systolic, widget.systolicKey,
                      VitalLimits.systolicBp),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 30, 8, 0),
                  child: Text('/', style: text.titleLarge?.copyWith(color: YomaColors.grey500)),
                ),
                Expanded(
                  child: _half('Diastolic', widget.diastolic, widget.diastolicKey,
                      VitalLimits.diastolicBp),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// AVPU as four large chips: starts unset, and "Not measured" is sent as null.
class AvpuField extends StatelessWidget {
  const AvpuField({
    super.key,
    required this.value,
    required this.onChanged,
    this.idPrefix = 'avpu',
  });

  static const notMeasured = 'NOT_MEASURED';

  /// The API value for a selection.
  static String? apiValue(String? selection) =>
      selection == notMeasured ? null : selection;

  /// Restores a selection recorded earlier in the session.
  static String? fromVitals(Map<String, Object?>? vitals) {
    const key = 'consciousness_level';
    if (vitals == null || !vitals.containsKey(key)) return null;
    return vitals[key]?.toString() ?? notMeasured;
  }

  static const _choices = [
    ('A', 'Alert'),
    ('V', 'Voice'),
    ('P', 'Pain'),
    ('U', 'Unresponsive'),
  ];

  final String? value;
  final ValueChanged<String?> onChanged;

  /// Chip keys are `<idPrefix>_A` … `<idPrefix>_U` and `<idPrefix>_not_measured`.
  final String idPrefix;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FormField<String>(
      // Rebuilt with the parent's value, so a restored selection shows.
      key: ValueKey('${idPrefix}_form_$value'),
      initialValue: value,
      validator: (v) => v == null ? 'Select AVPU or Not measured' : null,
      builder: (field) {
        void choose(String? next) {
          field.didChange(next);
          onChanged(next);
        }

        final isNotMeasured = field.value == notMeasured;
        return Padding(
          padding: const EdgeInsets.only(bottom: YomaSpacing.sm),
          child: YomaCard(
            color: isNotMeasured ? YomaColors.grey100 : YomaColors.surface,
            shadow: isNotMeasured ? const [] : YomaShadows.sm,
            borderColor: field.hasError ? YomaColors.error : YomaColors.grey200,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Consciousness',
                  style: text.titleMedium?.copyWith(
                    color: isNotMeasured ? YomaColors.grey600 : YomaColors.grey800,
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 8.0;
                    final width = (constraints.maxWidth - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final (code, label) in _choices)
                          SizedBox(
                            width: width,
                            child: YomaChoiceChip(
                              key: Key('${idPrefix}_$code'),
                              label: label,
                              selected: field.value == code,
                              semanticsHint: 'Consciousness',
                              onTap: () => choose(code),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                Row(
                  children: [
                    if (field.hasError)
                      Expanded(
                        child: Text(
                          field.errorText!,
                          style: text.bodySmall?.copyWith(
                            color: YomaColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    _NotMeasuredToggle(
                      toggleKey: Key('${idPrefix}_not_measured'),
                      notMeasured: isNotMeasured,
                      label: 'Consciousness',
                      onTap: () => choose(isNotMeasured ? null : notMeasured),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
