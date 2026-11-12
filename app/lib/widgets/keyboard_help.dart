/// Every key the app answers to, in one place.
///
/// Shown twice: written out on the Tutorial page, and in the dialog that `?`
/// opens from anywhere. One list for both, because a key list kept in two
/// places soon promises keys in one of them that no longer do anything.
///
/// The keys themselves are the ones people already know from elsewhere, so a
/// reader's habits carry over rather than having to be learned:
///
/// * `?` for this list and `/` for search, as in Gmail, GitHub and YouTube.
/// * J and K beside the arrows, from the same places.
/// * Alt and a number for the screens, as browsers and editors number their
///   tabs. Not Ctrl and a number, which the browser keeps for its own tabs.
/// * Arrows, Page Up and Down, Home and End through the rows, which is the
///   W3C's pattern for a list of options, and Escape to back out of anything.
///
/// **Keep this in step with the code that answers the keys**: the table's
/// `_onKey`, `HomeShell`'s app-wide keys, the tour, `AutocompleteField` and
/// `FilterableDropdown`. Nothing ties them together but this comment.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_selection.dart';

/// Whether the reader is typing into a box, where a plain key is a letter
/// and not a command. `?` and `/` have to be typeable.
bool isTypingText() {
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused != null &&
      focused.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// What the modifier keys are called on the reader's own keyboard. A Mac has
/// no key marked Alt, and its select-all is Command, not Control.
bool get _mac =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;
String get altKey => _mac ? 'Option' : 'Alt';
String get selectAllKey => _mac ? 'Cmd' : 'Ctrl';

typedef _Row = (List<String>, String);

List<(String, List<_Row>, String?)> _groups() => [
  (
    'Anywhere',
    [
      ([altKey, '1'], 'Data Display'),
      ([altKey, '2'], 'Advanced Search'),
      ([altKey, '3'], 'Tutorial'),
      (['?'], 'Show these keys'),
      (['Tab'], 'Next control'),
      (['Shift', 'Tab'], 'Previous control'),
      (['Enter'], 'Press the button you are on'),
      (['Esc'], 'Close a record, a menu or a message'),
    ],
    'In the list of screens on the left, the arrow keys move up and down '
        'it as well.',
  ),
  (
    'The table on Data Display',
    [
      (['↑', '↓'], 'Move the highlight one record'),
      (['J', 'K'], 'The same, down and up'),
      (['Page Up', 'Page Down'], 'Move it a screenful'),
      (['Home', 'End'], 'Go to the first or last record'),
      (['←', '→'], 'Scroll the columns sideways'),
      (['Enter'], 'Open the highlighted record to read'),
      (['Esc'], 'Drop the highlight'),
      (['/'], 'Jump to the search box'),
    ],
    'From the search box, Enter takes you back to the records. Tab from '
        'the table reaches the column headings, and Enter on a heading '
        'sorts by it; press it again to reverse.',
  ),
  (
    'Boxes you type into',
    [
      (['↑', '↓'], 'Move through the suggestions'),
      (['Enter'], 'Choose the one highlighted'),
      (['Backspace'], 'Clear a drop-down list back to Any'),
      ([selectAllKey, 'A'], 'Select what is typed, then Backspace to clear it'),
    ],
    null,
  ),
  (
    'The tour',
    [
      (['→', 'Enter'], 'Next'),
      (['←'], 'Back'),
      (['Esc'], 'Leave the tour'),
    ],
    null,
  ),
];

/// The whole list, laid out as keys and what they do.
class KeyboardShortcuts extends StatelessWidget {
  const KeyboardShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, rows, note) in groups)
          _KeyGroup(title: title, rows: rows, note: note),
      ],
    );
  }
}

/// Opens the list over whatever is on screen.
Future<void> showKeyboardHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Keyboard'),
    content: const SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: AppSelection(child: KeyboardShortcuts()),
      ),
    ),
    actions: [
      TextButton(
        autofocus: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);

class _KeyGroup extends StatelessWidget {
  const _KeyGroup({required this.title, required this.rows, this.note});
  final String title;
  final List<_Row> rows;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final (keys, does) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              // A column of keys beside a column of meanings where there is
              // room, and each meaning under its keys where there is not.
              // Decided once for the whole width, not row by row: a Wrap
              // dropped some descriptions and not others on a phone, and the
              // list stopped reading as a list.
              child: LayoutBuilder(
                builder: (context, box) {
                  final caps = Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final k in keys) _Keycap(k)],
                  );
                  final meaning = Text(does, style: theme.bodyMedium);
                  if (box.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [caps, const SizedBox(height: 2), meaning],
                    );
                  }
                  return Row(
                    children: [
                      SizedBox(width: 176, child: caps),
                      Expanded(child: meaning),
                    ],
                  );
                },
              ),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note!,
                style: theme.bodyMedium?.copyWith(height: 1.45),
              ),
            ),
        ],
      ),
    );
  }
}

/// A key drawn as a key, because that is what a reader scans for: the shape
/// of the key they are about to press, not the word for it.
class _Keycap extends StatelessWidget {
  const _Keycap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(5),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
          left: BorderSide(color: scheme.outlineVariant),
          right: BorderSide(color: scheme.outlineVariant),
          // A heavier bottom edge is what makes it read as a key.
          bottom: BorderSide(color: scheme.outline, width: 2),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
