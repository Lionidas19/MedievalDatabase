import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );
  late final FocusNode _focusNode = FocusNode();

  /// Follows a value changed from outside: picking from the dropdowns beside
  /// Advanced Search's item box rewrites what the box should say.
  ///
  /// That used to be done by keying the field on the choice, which threw the
  /// whole field away whenever the choice changed, including when the change
  /// came from this field. Choosing a suggestion therefore destroyed the box
  /// it was chosen in, and focus fell back to the navigation rail.
  ///
  /// Only when the value passed in has changed, and does not already match:
  /// the round trip from the reader's own typing must not move the caret.
  @override
  void didUpdateWidget(AutocompleteField old) {
    super.didUpdateWidget(old);
    final next = widget.initialValue ?? '';
    if (widget.initialValue != old.initialValue && _controller.text != next) {
      _controller.text = next;
    }
  }

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
        return widget.suggestions
            .where((s) => s.toLowerCase().contains(q))
            .take(50);
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
              // Out of the Tab order: from the keyboard, Ctrl+A and Backspace
              // do the same, and a stop per cross doubled the walk through
              // the editor's eleven fields.
              suffixIcon: value.text.isEmpty || !widget.enabled
                  ? null
                  : ExcludeFocus(
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear',
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          controller.clear();
                          widget.onChanged('');
                        },
                      ),
                    ),
              // Held to the icon's own size, or the button's 48px tap target
              // makes this field taller than the dropdowns beside it.
              suffixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            onChanged: widget.onChanged,
            // Enter takes the suggestion the arrow keys are on. Without this
            // the keyboard could move through the list but never choose from
            // it: Enter left the half-typed text standing, and in Advanced
            // Search that meant no item was chosen and Generate stayed off.
            onSubmitted: (_) => onSubmit(),
            // And stays put afterwards. A text field drops focus on Enter
            // by default, so after choosing, the next Tab started again from
            // the top of the page; supplying this skips that.
            onEditingComplete: () {},
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        // Which suggestion the arrow keys are on. Shown, and kept in view,
        // or a keyboard reader is choosing blind.
        final highlighted = AutocompleteHighlightedOption.of(context);
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
                  final current = i == highlighted;
                  // A Builder for the row's own context. The one handed to
                  // itemBuilder belongs to the whole list, and scrolling *that*
                  // into view centred the entire list instead of the row:
                  // the menu opened halfway down, away from the first choice.
                  return Builder(
                    builder: (row) {
                      if (current) {
                        // Moved only when the row would leave the list, past
                        // either edge; a list that jumps on every keypress
                        // is as hard to follow as one that never moves.
                        SchedulerBinding.instance.addPostFrameCallback((_) {
                          if (!row.mounted) return;
                          Scrollable.ensureVisible(
                            row,
                            alignmentPolicy:
                                ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                          );
                          Scrollable.ensureVisible(
                            row,
                            alignmentPolicy: ScrollPositionAlignmentPolicy
                                .keepVisibleAtStart,
                          );
                        });
                      }
                      // The arrow keys drive the highlight; the rows never
                      // need focus. Focusable, Tab fell into the open list,
                      // closed it, and came back to the box, so the keyboard
                      // could never leave the field.
                      return ExcludeFocus(
                        child: ListTile(
                          dense: true,
                          selected: current,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.14),
                          title: Text(option),
                          onTap: () => onSelected(option),
                        ),
                      );
                    },
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
          : (integer
                ? initialValue!.toInt().toString()
                : _trim(initialValue!.toDouble())),
      keyboardType: TextInputType.numberWithOptions(
        decimal: !integer,
        signed: true,
      ),
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
