import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/view_preferences.dart';
import '../../theme.dart';
import '../../widgets/item_label.dart';
import 'entry_columns.dart';

/// What one record says, with nothing editable on it.
///
/// Opening a row used to go straight to the editor. Watching people use the
/// app showed what that cost: one reader took the edit dialog for a search
/// box and changed a record without meaning to, and nobody could afterwards
/// say which record it had been. Reading is the common act and editing is the
/// rare one, so reading is what a tap now does, and editing needs the button
/// in the corner.
///
/// Built from [columnsFor] rather than from its own list of fields. The table
/// already knows every column's label, its value, its explanation and which
/// detail level it belongs to; a second copy of all that would drift from the
/// first within a month, and the two would then disagree about what a record
/// says.
Future<bool> showEntryDetails(
  BuildContext context, {
  required PricedEntry priced,
  required String unitName,
}) async {
  final wantsEdit = await showDialog<bool>(
    context: context,
    builder: (_) => _EntryDetailsDialog(priced: priced, unitName: unitName),
  );
  return wantsEdit ?? false;
}

class _EntryDetailsDialog extends StatelessWidget {
  const _EntryDetailsDialog({required this.priced, required this.unitName});

  final PricedEntry priced;
  final String unitName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = context.watch<ViewPreferences>().detailLevel;

    // The action column and the info button have nothing to read, and the
    // item is already the dialog's title — repeating it as a field says the
    // same thing twice in the first two lines.
    final columns = columnsFor(level, unitName)
        .where((c) => c.sortKey != null && c.id != 'item')
        .toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, scheme, theme),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                // Sized to what the record actually says. At Basics a record
                // is five lines, and a dialog stretched to 700px around them
                // reads as something that failed to load.
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                    Spacing.lg, Spacing.md, Spacing.lg, Spacing.md),
                children: [
                  for (var i = 0; i < columns.length; i++) ...[
                    // The table's own grouping — when and where, what it was,
                    // what it cost — carried across so a record reads in the
                    // same order in both places.
                    if (columns[i].startsGroup && i != 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: Spacing.sm),
                        child: Divider(height: 1),
                      ),
                    _Field(column: columns[i], priced: priced),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ColorScheme scheme, ThemeData theme) {
    final entry = priced.entry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.sm, Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // The item leads, with its specific carrying the weight — it
                // is what the record is *about*, and a reader should not have
                // to hunt for it behind a heading that says "Entry 496".
                ItemLabel(
                    entry: entry,
                    style: theme.textTheme.titleLarge,
                    emphasise: true),
                const SizedBox(height: 2),
                Text(
                  [
                    if (entry.year != null) '${entry.year}',
                    if (entry.locality != null) entry.locality!,
                    if (entry.county != null) entry.county!,
                    'entry ${entry.legacyEntryNo ?? '—'}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // "A button in the top right should be required to allow for
          // editing mode" — his words, and his placement. It sat in the
          // footer for a while because it read as a footer action; his
          // instruction is the one that counts.
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          const SizedBox(width: Spacing.sm),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Showing what the source records. Nothing here is editable.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),

        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.column, required this.priced});

  final EntryColumn column;
  final PricedEntry priced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = column.value(priced);
    // Why this particular cell is blank, where the column knows.
    final note = column.cellTooltip?.call(priced);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    column.label,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (column.explanation != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    constraints: const BoxConstraints(maxWidth: 380),
                    message: column.explanation!,
                    triggerMode: TooltipTriggerMode.tap,
                    showDuration: const Duration(seconds: 12),
                    child: Icon(Icons.info_outline,
                        size: 14, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  value.isEmpty ? '—' : value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontFeatures:
                        column.numeric ? const [tabularFigures] : null,
                  ),
                ),
                if (note != null)
                  Text(
                    note,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
