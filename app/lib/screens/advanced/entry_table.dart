import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../theme.dart';
import 'entry_columns.dart';

/// A run of entries under one heading.
///
/// [median] is the middle price per the chosen unit *within this group*, which
/// is the figure the Specifics lookup screen would give for the same selection.
/// Putting it in the header means a reader scanning by year or county gets
/// that answer without leaving the table.
class EntryGroup {
  const EntryGroup({
    required this.label,
    required this.rows,
    required this.median,
    required this.pricedCount,
  });

  final String label;
  final List<PricedEntry> rows;
  final double? median;

  /// How many of [rows] could actually be priced. The rest are excluded from
  /// [median] rather than counted as zero.
  final int pricedCount;
}

/// The Explorer's table.
///
/// Scrolls in both directions: the header travels with the body horizontally,
/// so columns stay aligned, and group headings pin to the top on the way down.
class EntryTable extends StatefulWidget {
  const EntryTable({
    super.key,
    required this.groups,
    required this.columns,
    required this.rowHeight,
    required this.sortColumnId,
    required this.ascending,
    required this.onSort,
    required this.onOpen,
    required this.unitName,
    required this.showGroupHeaders,
  });

  final List<EntryGroup> groups;
  final List<EntryColumn> columns;
  final double rowHeight;
  /// The id of the column being sorted on, or null for none.
  final String? sortColumnId;
  final bool ascending;
  final ValueChanged<EntryColumn> onSort;
  final ValueChanged<PriceEntry> onOpen;
  final String unitName;
  final bool showGroupHeaders;

  @override
  State<EntryTable> createState() => _EntryTableState();
}

class _EntryTableState extends State<EntryTable> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  static const _actionsWidth = 52.0;

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  double get _totalWidth =>
      widget.columns.fold<double>(0, (sum, c) => sum + c.width) + _actionsWidth;

  /// Column widths for the space actually available.
  ///
  /// Past the point where the columns fit, they keep the widths they were
  /// given and the table scrolls. Short of it, the slack goes to the columns
  /// holding names and notes, in proportion to what they already had — a place
  /// name has more to gain from another forty pixels than a page number does,
  /// and a numeric column that grows just pushes its figures further from the
  /// ones above them.
  List<double> _widths(double available) {
    final widths = [for (final c in widget.columns) c.width];
    final slack = available - _totalWidth;
    if (slack <= 0) return widths;

    final flexible = [
      for (var i = 0; i < widget.columns.length; i++)
        if (!widget.columns[i].numeric) i,
    ];
    if (flexible.isEmpty) return widths;

    final flexTotal =
        flexible.fold<double>(0, (sum, i) => sum + widths[i]);
    for (final i in flexible) {
      widths[i] += slack * widths[i] / flexTotal;
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final headerHeight = widget.rowHeight * 0.85;

    // At the narrower detail levels the columns do not fill the window, and a
    // scroll view given a child smaller than itself leaves it floating in the
    // middle with dead margins either side. Stretching to the wider of the two
    // keeps the rows and their dividers running the full width, and the
    // sideways scrollbar appears only when there is genuinely more to reach.
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrolls = _totalWidth > constraints.maxWidth;
        final width = scrolls ? _totalWidth : constraints.maxWidth;
        final widths = _widths(constraints.maxWidth);

        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: scrolls,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            physics: scrolls ? null : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  _header(context, widths),
                  Divider(height: 1, color: scheme.outlineVariant),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertical,
                      child: CustomScrollView(
                        controller: _vertical,
                        slivers: [
                          for (final group in widget.groups)
                            if (widget.showGroupHeaders)
                              SliverMainAxisGroup(
                                slivers: [
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _GroupHeaderDelegate(
                                      group: group,
                                      height: headerHeight,
                                      unitName: widget.unitName,
                                      scheme: scheme,
                                      textTheme: Theme.of(context).textTheme,
                                      horizontal: _horizontal,
                                      viewportWidth: constraints.maxWidth,
                                    ),
                                  ),
                                  _rowsSliver(group, widths),
                                ],
                              )
                            else
                              _rowsSliver(group, widths),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _rowsSliver(EntryGroup group, List<double> widths) =>
      SliverFixedExtentList(
        itemExtent: widget.rowHeight,
        delegate: SliverChildBuilderDelegate(
          (context, i) => _EntryRow(
            priced: group.rows[i],
            columns: widget.columns,
            widths: widths,
            actionsWidth: _actionsWidth,
            onOpen: widget.onOpen,
            // Banded within the group, so a heading always restarts the
            // pattern rather than inheriting whatever parity it landed on.
            shaded: i.isOdd,
          ),
          childCount: group.rows.length,
        ),
      );

  Widget _header(BuildContext context, List<double> widths) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHigh,
      height: widget.rowHeight * 0.85,
      child: Row(
        children: [
          for (final (i, column) in widget.columns.indexed)
            _Seam(
              column: column,
              first: i == 0,
              strong: true,
              child: SizedBox(
                width: widths[i],
                child: _HeaderCell(
                  column: column,
                  active: column.id == widget.sortColumnId,
                  ascending: widget.ascending,
                  onSort: column.sortKey == null
                      ? null
                      : () => widget.onSort(column),
                ),
              ),
            ),
          const SizedBox(width: _actionsWidth),
        ],
      ),
    );
  }
}

/// One column heading: its name, the sort arrow, and — where the column needs
/// explaining — a button that says what it means.
///
/// The explanation has to reach two kinds of reader. On a desktop the pointer
/// hovering over the heading is enough. On a touch screen there is no hover at
/// all, and the obvious gesture is already taken: tapping a heading sorts by
/// it. So the explanation gets its own small target, and the tooltip is put
/// into manual mode and opened from it. Hover is unaffected by that mode, so
/// one message serves both without a second code path.
class _HeaderCell extends StatefulWidget {
  const _HeaderCell({
    required this.column,
    required this.active,
    required this.ascending,
    required this.onSort,
  });

  final EntryColumn column;
  final bool active;
  final bool ascending;
  final VoidCallback? onSort;

  @override
  State<_HeaderCell> createState() => _HeaderCellState();
}

class _HeaderCellState extends State<_HeaderCell> {
  final _tip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final column = widget.column;
    final scheme = Theme.of(context).colorScheme;

    // An explanation is worth hovering as well as asking for; a plain tooltip
    // is hover-only by design.
    final message = column.explanation ?? column.tooltip;

    final info = column.explanation == null
        ? null
        : Semantics(
            button: true,
            label: 'What does ${column.label} mean?',
            child: InkWell(
              // Its own target rather than the whole heading, so it cannot be
              // mistaken for the sort. Full height, because 13px of icon is
              // not something a thumb can find.
              onTap: () => _tip.currentState?.ensureTooltipVisible(),
              child: SizedBox(
                width: 22,
                height: double.infinity,
                child: Icon(
                  Icons.info_outline,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );

    final name = Flexible(
      child: Text(
        column.label,
        textAlign: column.numeric ? TextAlign.right : TextAlign.left,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: widget.active ? FontWeight.w700 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );

    final arrow = widget.active
        ? Icon(
            widget.ascending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 13,
          )
        : null;

    // A numeric heading sits over right-aligned figures, so it is right-aligned
    // too and the info button goes on its far side — otherwise the button
    // wedges itself between the heading and the column of numbers it names.
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: column.numeric
          ? [?info, name, ?arrow]
          : [name, ?arrow, ?info],
    );

    final cell = Padding(
      padding: EdgeInsets.only(
        left: column.numeric && info != null ? 2 : Spacing.sm,
        right: !column.numeric && info != null ? 2 : Spacing.sm,
      ),
      child: Align(
        alignment:
            column.numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: label,
      ),
    );

    final withTooltip = message == null
        ? cell
        : Tooltip(
            key: _tip,
            message: message,
            // Manual only governs touch: a mouse still shows it on hover.
            triggerMode: column.explanation != null
                ? TooltipTriggerMode.manual
                : TooltipTriggerMode.longPress,
            preferBelow: true,
            // Long enough to read a sentence on a phone before it goes.
            showDuration: const Duration(seconds: 8),
            constraints: const BoxConstraints(maxWidth: 320),
            child: cell,
          );

    return widget.onSort == null
        ? withTooltip
        : InkWell(onTap: widget.onSort, child: withTooltip);
  }
}

/// A pinned heading for one group of rows.
class _GroupHeaderDelegate extends SliverPersistentHeaderDelegate {
  _GroupHeaderDelegate({
    required this.group,
    required this.height,
    required this.unitName,
    required this.scheme,
    required this.textTheme,
    required this.horizontal,
    required this.viewportWidth,
  });

  final EntryGroup group;
  final double height;
  final String unitName;
  final ColorScheme scheme;
  final TextTheme textTheme;

  /// The table's sideways scroll, and how much of it is on screen.
  ///
  /// The heading lives inside that scroll view along with the rows, so at the
  /// wider detail levels it slid off to the left the moment anybody scrolled
  /// right — leaving a labelled band with no label on it. Its contents are
  /// pushed back by the scroll offset and held to the width actually visible,
  /// so the year and its median stay readable while the columns travel
  /// underneath.
  final ScrollController horizontal;
  final double viewportWidth;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final count = group.rows.length;
    // Report the sample the median actually came from. A median over 3 of 40
    // entries is a different claim from a median over all 40, and the header
    // is exactly where somebody would otherwise assume the latter.
    final summary = group.median == null
        ? 'none priced per $unitName'
        : 'median ${formatPence(group.median)} pence per $unitName, '
              'from ${group.pricedCount} of $count';

    return Container(
      height: height,
      color: scheme.surfaceContainer,
      child: AnimatedBuilder(
        animation: horizontal,
        builder: (context, child) => Transform.translate(
          offset: Offset(horizontal.hasClients ? horizontal.offset : 0, 0),
          // Align, not a bare SizedBox: the sliver hands down a tight width of
          // the whole scrollable row, and a SizedBox cannot be narrower than a
          // tight constraint — it was silently stretching back to the full
          // 3,400px and posting the median off the right-hand edge.
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(width: viewportWidth, child: child),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: Row(
            children: [
              Text(
                group.label,
                style:
                    textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                '$count ${count == 1 ? 'entry' : 'entries'}',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Spacing.md),
              // Expanded with a right-aligned Text, rather than a Spacer and a
              // fixed one. A Spacer would either share the free space with a
              // Flexible sibling (parking the median mid-band) or leave a
              // fixed sibling unable to shrink — which is how a longer wording
              // overflowed this row rather than ellipsing.
              Expanded(
                child: Text(
                  summary,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [tabularFigures],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _GroupHeaderDelegate old) =>
      old.group != group ||
      old.height != height ||
      old.unitName != unitName ||
      old.scheme != scheme ||
      old.viewportWidth != viewportWidth ||
      old.horizontal != horizontal;
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.priced,
    required this.columns,
    required this.widths,
    required this.actionsWidth,
    required this.onOpen,
    required this.shaded,
  });

  final PricedEntry priced;
  final List<EntryColumn> columns;
  final List<double> widths;
  final double actionsWidth;

  /// Every other row, tinted. Twenty-three columns is a long way for an eye to
  /// travel without losing its line, and a band carries it further than a rule
  /// between rows does — which is why that rule is gone.
  final bool shaded;
  final ValueChanged<PriceEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodyMedium;

    return Material(
      color: shaded ? scheme.surfaceContainerLow : scheme.surface,
      child: InkWell(
        onTap: () => onOpen(priced.entry),
        child: Row(
          children: [
            for (final (i, column) in columns.indexed)
              _Seam(
                column: column,
                first: i == 0,
                strong: false,
                child: SizedBox(
                  width: widths[i],
                  child: _Cell(
                    column: column,
                    priced: priced,
                    style: base,
                    mutedColor: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            SizedBox(
              width: actionsWidth,
              child: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit this entry',
                onPressed: () => onOpen(priced.entry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the line where one run of columns gives way to the next.
class _Seam extends StatelessWidget {
  const _Seam({
    required this.column,
    required this.first,
    required this.strong,
    required this.child,
  });

  final EntryColumn column;
  final bool first;

  /// Headings carry the seam plainly; rows only hint at it, or the table turns
  /// into a grid of boxes.
  final bool strong;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!column.startsGroup || first) return child;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: strong ? 0.9 : 0.4),
          ),
        ),
      ),
      child: child,
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.column,
    required this.priced,
    required this.style,
    required this.mutedColor,
  });

  final EntryColumn column;
  final PricedEntry priced;
  final TextStyle? style;
  final Color mutedColor;

  /// Roughly how wide [text] will render at the table's 14px body size.
  ///
  /// An estimate rather than a measurement: laying out a TextPainter for every
  /// cell would cost a few hundred layouts a frame to answer a question only
  /// the long values care about. It errs generously, so the worst case is a
  /// tooltip repeating something already legible.
  static const _perCharacter = 7.4;

  @override
  Widget build(BuildContext context) {
    final text = column.value(priced);
    final absent = text == '—';
    // An estimate must never be mistakable for a record, so it is set apart in
    // slant and colour as well as marked with a tilde.
    final estimated = text.startsWith('~');
    // Only a value too long for its column gets one; hovering '1270' to be
    // told '1270' is noise.
    final clipped =
        text.length * _perCharacter > column.width - Spacing.sm * 2;

    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      child: Align(
        alignment: column.numeric
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: column.numeric ? TextAlign.right : TextAlign.left,
          style: style?.copyWith(
            color: absent || estimated ? mutedColor : null,
            fontStyle: estimated ? FontStyle.italic : null,
            fontFeatures: column.numeric ? const [tabularFigures] : null,
          ),
        ),
      ),
    );

    // Only build a Tooltip where there is something to say. The old table
    // wrapped every per-unit cell in one and passed an empty message.
    final message =
        column.cellTooltip?.call(priced) ?? (clipped && !absent ? text : null);
    return message == null
        ? child
        : Tooltip(
            message: message,
            waitDuration: const Duration(milliseconds: 400),
            constraints: const BoxConstraints(maxWidth: 360),
            child: child,
          );
  }
}
