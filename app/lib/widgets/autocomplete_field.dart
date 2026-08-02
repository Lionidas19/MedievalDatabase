import 'package:flutter/material.dart';

/// A text field with suggestion dropdown that still accepts arbitrary free
/// text (so editors can either pick an existing lookup value or type a new
/// one — new values get created in the matching lookup table on save).
class AutocompleteField extends StatelessWidget {
  const AutocompleteField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.suggestions,
    required this.onChanged,
    this.enabled = true,
    this.helperText,
  });

  final String label;
  final String? initialValue;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: TextEditingController(text: initialValue ?? ''),
      focusNode: FocusNode(),
      optionsBuilder: (value) {
        if (value.text.isEmpty) return suggestions.take(50);
        final q = value.text.toLowerCase();
        return suggestions.where((s) => s.toLowerCase().contains(q)).take(50);
      },
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          decoration: InputDecoration(labelText: label, helperText: helperText),
          onChanged: onChanged,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final option = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A compact numeric field bound to a nullable double, used throughout the
/// edit form.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.integer = false,
  });

  final String label;
  final num? initialValue;
  final ValueChanged<num?> onChanged;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue == null
          ? ''
          : (integer ? initialValue!.toInt().toString() : _trim(initialValue!.toDouble())),
      keyboardType: TextInputType.numberWithOptions(decimal: !integer, signed: true),
      decoration: InputDecoration(labelText: label),
      onChanged: (text) {
        if (text.trim().isEmpty) {
          onChanged(null);
          return;
        }
        final parsed = integer ? int.tryParse(text) : double.tryParse(text);
        onChanged(parsed);
      },
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
