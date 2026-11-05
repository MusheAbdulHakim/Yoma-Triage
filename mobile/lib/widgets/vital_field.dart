import 'package:flutter/material.dart';

import '../theme/yoma_theme.dart';

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

  int? get intValue => notMeasured ? null : int.tryParse(controller.text.trim());

  double? get doubleValue =>
      notMeasured ? null : double.tryParse(controller.text.trim());

  void setValue(Object value) {
    notMeasured = false;
    controller.text = value.toString();
  }

  void dispose() => controller.dispose();
}

class VitalField extends StatefulWidget {
  const VitalField({
    super.key,
    required this.input,
    required this.label,
    required this.fieldKey,
    this.decimal = false,
    this.highlight = false,
    this.helperText,
  });

  final VitalInput input;
  final String label;

  /// Key of the text field; the checkbox is `<fieldKey>_not_measured`.
  final String fieldKey;
  final bool decimal;
  final bool highlight;
  final String? helperText;

  @override
  State<VitalField> createState() => _VitalFieldState();
}

class _VitalFieldState extends State<VitalField> {
  String? _validate(String? value) {
    if (widget.input.notMeasured) return null;
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return 'Enter a value or tick Not measured';
    final parsed = widget.decimal ? double.tryParse(raw) : int.tryParse(raw);
    if (parsed == null) {
      return widget.decimal ? 'Invalid number' : 'Invalid whole number';
    }
    return null;
  }

  void _setNotMeasured(bool value) {
    setState(() {
      widget.input.notMeasured = value;
      if (value) widget.input.controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notMeasured = widget.input.notMeasured;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: Key(widget.fieldKey),
            controller: widget.input.controller,
            enabled: !notMeasured,
            keyboardType:
                TextInputType.numberWithOptions(decimal: widget.decimal),
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: widget.helperText,
              helperMaxLines: 2,
              errorMaxLines: 2,
              filled: widget.highlight,
              fillColor: widget.highlight
                  ? YomaColors.danger.withValues(alpha: 0.08)
                  : null,
              enabledBorder: widget.highlight
                  ? const OutlineInputBorder(
                      borderSide:
                          BorderSide(color: YomaColors.danger, width: 1.5),
                    )
                  : null,
            ),
            validator: _validate,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: InkWell(
            key: Key('${widget.fieldKey}_not_measured'),
            onTap: () => _setNotMeasured(!notMeasured),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeFocus(
                  child: Checkbox(
                    value: notMeasured,
                    onChanged: (v) => _setNotMeasured(v ?? false),
                  ),
                ),
                const Text('Not measured', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// AVPU picker: starts unset, and "Not measured" is sent as null.
class AvpuField extends StatelessWidget {
  const AvpuField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const notMeasured = 'NOT_MEASURED';

  /// The API value for a dropdown selection.
  static String? apiValue(String? selection) =>
      selection == notMeasured ? null : selection;

  /// Restores a selection recorded earlier in the session.
  static String? fromVitals(Map<String, Object?>? vitals) {
    const key = 'consciousness_level';
    if (vitals == null || !vitals.containsKey(key)) return null;
    return vitals[key]?.toString() ?? notMeasured;
  }

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'AVPU'),
      items: const [
        DropdownMenuItem(value: 'A', child: Text('A — Alert')),
        DropdownMenuItem(value: 'V', child: Text('V — Voice')),
        DropdownMenuItem(value: 'P', child: Text('P — Pain')),
        DropdownMenuItem(value: 'U', child: Text('U — Unresponsive')),
        DropdownMenuItem(value: notMeasured, child: Text('Not measured')),
      ],
      onChanged: onChanged,
      validator: (v) => v == null ? 'Select AVPU or Not measured' : null,
    );
  }
}
