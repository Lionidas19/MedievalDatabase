import 'package:flutter/material.dart';

import '../models/models.dart';

/// What a record says beyond its item, quantity and price, as label and text.
///
/// Three fields of the source that fit no other column: Status Info, where the
/// researcher noted the form a thing took ("Seed", "Crannock", "Old"); Food,
/// beside labour, for whether part of the pay came as food; and Information,
/// the occasional Latin gloss. A row reading `Other / Other / Other` is
/// meaningless without them, and they used to be visible only at Everything,
/// twenty columns to the right of the item they explain.
///
/// Blank and whitespace-only values are not notes.
List<(String, String)> recordNotes(PriceEntry e) => [
  for (final (label, value) in [
    ('Note', e.statusInfo),
    ('Paid in food', e.food),
    ('Information', e.information),
  ])
    if (value != null && value.trim().isNotEmpty) (label, value.trim()),
];

/// A small mark beside the item, present only when the record has notes.
///
/// The researcher's own suggestion: a column in the database, but not in the
/// table. A column of these would be dashes in all but one row in ten, and
/// the place the eye goes for "what *kind* of other?" is the item itself.
/// It also frees the notes from the width of a column, so they can run to a
/// sentence rather than two or three words.
///
/// Hover shows them; a tap does too, for the tablets that have no hover. The
/// same arrangement as `InfoDot` and the column headings, for the same
/// reason. Being an `InkWell` of its own, the tap is not also taken as a tap
/// on the row.
class RecordNotesMark extends StatefulWidget {
  const RecordNotesMark({super.key, required this.entry, this.size = 15});

  final PriceEntry entry;
  final double size;

  @override
  State<RecordNotesMark> createState() => _RecordNotesMarkState();
}

class _RecordNotesMarkState extends State<RecordNotesMark> {
  final _tip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final notes = recordNotes(widget.entry);
    if (notes.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final message = notes.map((n) => '${n.$1}: ${n.$2}').join('\n');

    return Tooltip(
      key: _tip,
      message: message,
      triggerMode: TooltipTriggerMode.manual,
      waitDuration: const Duration(milliseconds: 250),
      showDuration: const Duration(seconds: 10),
      constraints: const BoxConstraints(maxWidth: 380),
      child: Semantics(
        button: true,
        label: 'Notes on this record',
        child: InkWell(
          onTap: () => _tip.currentState?.ensureTooltipVisible(),
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(
              Icons.sticky_note_2_outlined,
              size: widget.size,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
