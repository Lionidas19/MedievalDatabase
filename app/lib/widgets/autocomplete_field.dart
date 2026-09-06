import 'package:flutter/material.dart';

/// A text field with suggestion dropdown that still accepts arbitrary free
/// text (so editors can either pick an existing lookup value or type a new
/// one — new values get created in the matching lookup table on save).
class AutocompleteField extends StatefulWidget {
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
  State<AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<AutocompleteField> {
  // Held in state rather than rebuilt each time: a controller created in
  // build() would be replaced on every rebuild, discarding whatever the editor
  // had typed, and a FocusNode created there would leak.
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');
  late final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        if (value.text.isEmpty) return widget.suggestions.take(50);
        final q = value.text.toLowerCase();
        return widget.suggestions.where((s) => s.toLowerCase().contains(q)).take(50);
      },
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        // Listening to the controller rather than calling setState from
        // onChanged: the cross has to appear the moment there is text and go
        // again the moment there is none, including when the text arrived by
        // picking a suggestion rather than by typing.
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: widget.helperText,
              // A field with no list to fall back on needs its own way out.
              // Selecting the text and deleting it works, but it is not
              // something a reader thinks to do, and on a phone it is fiddly.
              suffixIcon: value.text.isEmpty || !widget.enabled
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear',
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        controller.clear();
                        widget.onChanged('');
                      },
                    ),
              // Held to the icon's own size, or the button's 48px tap target
              // makes this field taller than the dropdowns beside it.
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            onChanged: widget.onChanged,
          ),
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
