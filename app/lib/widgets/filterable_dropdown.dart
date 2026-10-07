import 'package:flutter/material.dart';

/// A dropdown you can type into, that keeps only what it offered.
///
/// `DropdownMenu` is a text field with a menu attached, and by default it does
/// neither of the two things a reader expects of that: typing does not narrow
/// the list, and whatever is typed simply stays. A category could be left
/// reading 'dasdwadsd' — a value no record has, silently filtering everything
/// away.
///
/// So: typing filters the options, and anything left in the box that is not
/// one of them is put back to the current selection when the field loses
/// focus. There is no third state where the box says one thing and the query
/// means another.
class FilterableDropdown<T> extends StatefulWidget {
  const FilterableDropdown({
    super.key,
    required this.width,
    required this.value,
    required this.hint,
    this.label,
    required this.entries,
    required this.onSelected,
    this.enabled = true,
  });

  final double width;
  final T value;
  final String hint;

  /// The floating label above the field, where the control needs naming.
  ///
  /// The Specifics lookup names its controls in the sentence around them —
  /// "or pick:", "returned value as pence per" — so it passes none. The
  /// Explorer's toolbar has no such sentence, and "Price per" is the one
  /// control readers said they did not understand; losing its name would make
  /// that worse, not better.
  final String? label;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final bool enabled;

  /// Whether the list offers a "no choice" row, and so whether un-choosing is
  /// a thing the reader can mean here.
  bool get canClear => entries.any((e) => e.value == null);

  @override
  State<FilterableDropdown<T>> createState() => _FilterableDropdownState<T>();
}

class _FilterableDropdownState<T> extends State<FilterableDropdown<T>> {
  final _controller = TextEditingController();

  /// Whether the control or anything inside it holds focus.
  ///
  /// Observed from the outside with a [Focus] wrapper rather than by handing
  /// `DropdownMenu` a FocusNode of our own: doing the latter stops its text
  /// field from ever taking focus, so typing reaches nothing and the list
  /// never filters. That cost an hour; do not put it back.
  bool _hasFocus = false;

  String get _selectedLabel {
    for (final e in widget.entries) {
      if (e.value == widget.value) return e.label;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _controller.text = _selectedLabel;
  }

  @override
  void didUpdateWidget(FilterableDropdown<T> old) {
    super.didUpdateWidget(old);
    // Follow a selection made elsewhere — choosing a category empties the
    // subcategory beneath it, and the box has to say so.
    if (widget.value != old.value && _controller.text != _selectedLabel) {
      _controller.text = _selectedLabel;
    }
  }

  /// Highlights the whole label the moment the field is entered.
  ///
  /// The caret otherwise lands wherever the reader happened to click, so the
  /// first keystroke goes *into* the label: clicking the middle of "Any
  /// category" and typing "produce" leaves "Any cateproducegory", which
  /// matches nothing, and the menu opens empty. Highlighted, the label stays
  /// readable and the first keystroke replaces it — what a box you can type
  /// into is expected to do. It also makes a single Backspace enough to empty
  /// the field, which is how a choice gets undone from the keyboard.
  ///
  /// After the frame, because the tap that handed us focus places the caret
  /// itself, and does that later than this callback runs.
  void _selectAllOnEntry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasFocus) return;
      _controller.selection =
          TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    });
  }

  /// Puts junk back once the field is really finished with.
  ///
  /// A moment's grace first: focus flickers as the menu opens and closes, and
  /// restoring on the first blur would wipe what is being typed.
  void _restoreOnBlur() {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || _hasFocus) return;
      final text = _controller.text.trim();
      if (text == _selectedLabel) return;

      // An emptied box means the reader wants nothing chosen here. The first
      // version simply put the old value back, so a category once chosen
      // could not be un-chosen at all.
      if (text.isEmpty && widget.canClear) {
        if (widget.value != null) widget.onSelected(null as T);
        return;
      }
      // Text naming a real option is a reader mid-thought, not junk.
      if (widget.entries.any((e) => e.label == text)) return;
      _controller.text = _selectedLabel;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        _hasFocus = has;
        if (has) {
          _selectAllOnEntry();
        } else {
          _restoreOnBlur();
        }
      },
      child: SizedBox(
        width: widget.width,
        child: DropdownMenu<T>(
          width: widget.width,
          enabled: widget.enabled,
          hintText: widget.hint,
          label: widget.label == null ? null : Text(widget.label!),
          controller: _controller,
          initialSelection: widget.value,
          // The two that make typing mean something.
          enableFilter: true,
          requestFocusOnTap: true,
          // Bounded, so the menu drops below the field instead of growing
          // tall enough that it has to flip up and cover the very text being
          // typed into it.
          menuHeight: 320,
          // A cross while something is chosen, in place of the arrow.
          //
          // The list does carry an "Any ..." row, but the menu opens scrolled
          // to whatever is selected, so that row is usually above the fold and
          // no help at all. Un-choosing needs to be visible without hunting.
          trailingIcon: widget.value != null && widget.canClear
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear',
                  onPressed: () {
                    _controller.clear();
                    widget.onSelected(null as T);
                  },
                )
              : null,
          dropdownMenuEntries: widget.entries,
          onSelected: (v) {
            if (v != null || widget.entries.any((e) => e.value == null)) {
              widget.onSelected(v as T);
            }
          },
        ),
      ),
    );
  }
}

/// Options that would find nothing, sent to the bottom and struck through.
///
/// Advanced Search has done this since it was written, and the researcher
/// asked for the same in Data Display: an option that cannot produce a row is
/// worse than useless, because choosing it looks like the app breaking. So a
/// dead option is still listed, in its own group at the end, crossed out and
/// marked `(none)` and disabled.
///
/// The current selection stays enabled whatever its count, so nobody is
/// stranded on a value they cannot leave.
List<DropdownMenuEntry<T>> facetEntries<T>(
  BuildContext context, {
  required List<(T, String)> options,
  required bool Function(T) available,
  required T? selected,
  DropdownMenuEntry<T>? anyOption,
}) {
  final live = <DropdownMenuEntry<T>>[];
  final dead = <DropdownMenuEntry<T>>[];
  for (final (value, label) in options) {
    if (available(value) || value == selected) {
      live.add(DropdownMenuEntry(value: value, label: label));
    } else {
      dead.add(
        DropdownMenuEntry(
          value: value,
          label: label,
          enabled: false,
          labelWidget: Text(
            '$label  (none)',
            style: TextStyle(
              decoration: TextDecoration.lineThrough,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
  }
  return [?anyOption, ...live, ...dead];
}
