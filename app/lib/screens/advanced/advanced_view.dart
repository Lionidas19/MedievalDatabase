import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../services/statistics.dart';
import '../../services/trend.dart';
import '../../state/app_controller.dart';
import '../../state/view_preferences.dart';
import '../../theme.dart';
import 'edit_entry_dialog.dart';
import 'entry_columns.dart';
import 'entry_table.dart';
import 'filter_bar.dart';

/// Opens the editor for [entry], wiring up save and delete.
///
/// Kept in one place because every list in the app opens the same dialog and
/// they must all behave identically — a delete that works in the table but
/// not in the compact list is exactly the kind of inconsistency nobody
/// notices until it matters.
Future<void> openEntryEditor(BuildContext context, PriceEntry entry) async {
  final app = context.read<AppController>();
  final messenger = ScaffoldMessenger.of(context);
  final updated = await showEditEntryDialog(
    context,
    entry: entry,
    repository: app.repository,
    onDelete: () {
      app.deleteEntry(entry.entryId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted entry #${entry.legacyEntryNo ?? ''}'),
        ),
      );
    },
  );
  if (updated != null) app.applyEdit(updated);
}

/// Identifies one filtered, priced, sorted and grouped result.
///
/// The pipeline behind it walks 7,800 entries, runs the calculation chain on
/// each and sorts the lot. It used to run inside `build()`, which meant it ran
/// again every time the save indicator ticked over from "Saving…" to "Saved".
/// Nothing in this key changes when that happens.
class _ResultKey {
  const _ResultKey({
    required this.revision,
    required this.search,
    required this.county,
    required this.category,
    required this.dateFilter,
    required this.yearStart,
    required this.yearEnd,
    required this.unitId,
    required this.sortColumnId,
    required this.ascending,
    required this.groupBy,
    required this.estimating,
  });

  final int revision;
  final String search;
  final String? county;
  final String? category;
  final DateFilter dateFilter;
  final double yearStart;
  final double yearEnd;
  final String? unitId;
  final String? sortColumnId;
  final bool ascending;
  final GroupBy groupBy;
  final bool estimating;

  @override
  bool operator ==(Object other) =>
      other is _ResultKey &&
      other.revision == revision &&
      other.search == search &&
      other.county == county &&
      other.category == category &&
      other.dateFilter == dateFilter &&
      other.yearStart == yearStart &&
      other.yearEnd == yearEnd &&
      other.unitId == unitId &&
      other.sortColumnId == sortColumnId &&
      other.ascending == ascending &&
      other.groupBy == groupBy &&
      other.estimating == estimating;

  @override
  int get hashCode => Object.hash(revision, search, county, category,
      dateFilter, yearStart, yearEnd, unitId, sortColumnId, ascending, groupBy,
      estimating);
}

class AdvancedView extends StatefulWidget {
  const AdvancedView({super.key, this.active = true});

  /// Whether this is the view currently on screen.
  ///
  /// Only the visible view subscribes to settings and data. An off-screen view
  /// that listens is rebuilt on every change nobody asked it to react to,
  /// which is work spent on pixels that do not exist. It picks up whatever
  /// changed the moment it is shown again, because switching views rebuilds
  /// both of them anyway.
  final bool active;

  @override
  State<AdvancedView> createState() => _AdvancedViewState();
}

class _AdvancedViewState extends State<AdvancedView> {
  FilterState _filters = const FilterState();
  MetricItem? _outputUnit;

  /// Which column orders the table, by [EntryColumn.id]. An id rather than the
  /// column itself, because the column list is rebuilt whenever the detail
  /// level or the output unit changes.
  String _sortColumnId = 'year';
  bool _ascending = true;

  /// Off by default, and deliberately so. Every other figure here is something
  /// the source says; these are guesses, and a reader should have to ask.
  bool _estimating = false;

  _ResultKey? _cacheKey;
  List<EntryGroup> _cached = const [];
  int _matchCount = 0;

  /// The middle, average and commonest price across everything the filters
  /// left, in the chosen unit. Computed in the same pass as the rows.
  ///
  /// Estimates are not in it. They are not observations, and an average that
  /// quietly absorbed them would be the exact failure this whole feature has
  /// to avoid.
  PriceStats _stats = PriceStats.empty;

  /// How many rows carry a guess rather than a figure.
  int _estimateCount = 0;

  /// The same figures again, this time counting the guesses.
  ///
  /// Null unless estimating is on. Shown *beside* the recorded ones rather
  /// than instead of them: the reader asked for estimates to be taken into
  /// account, and can only judge what that did by seeing both.
  PriceStats? _statsWithEstimates;

  void _toggleSort(EntryColumn column) {
    setState(() {
      if (_sortColumnId == column.id) {
        _ascending = !_ascending;
      } else {
        _sortColumnId = column.id;
        _ascending = true;
      }
    });
  }

  /// Orders two rows by whatever the sorted column says to order them by.
  ///
  /// Missing values sort last in *both* directions. A row with no page number
  /// is not a row with a low one, and flipping the sort should not parade the
  /// blanks to the top.
  int _compare(SortKey key, PricedEntry a, PricedEntry b) {
    final x = key(a);
    final y = key(b);
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    final cmp = compareSortKeys(x, y);
    return _ascending ? cmp : -cmp;
  }

  /// Filters, prices, sorts and groups — once per distinct [_ResultKey].
  List<EntryGroup> _results(
      AppController app, ViewPreferences prefs, EntryColumn? sortColumn) {
    final key = _ResultKey(
      revision: app.revision,
      search: _filters.search.trim().toLowerCase(),
      county: _filters.county,
      category: _filters.category,
      dateFilter: _filters.dateFilter,
      yearStart: _filters.years?.start ?? 0,
      yearEnd: _filters.years?.end ?? 0,
      unitId: _outputUnit?.id,
      sortColumnId: sortColumn?.id,
      ascending: _ascending,
      groupBy: prefs.groupBy,
      estimating: _estimating,
    );
    if (key == _cacheKey) return _cached;

    final priced = <PricedEntry>[];
    for (final e in app.entries) {
      if (!_filters.matches(e)) continue;
      // A price per kilogram for something sold by the head is a number the
      // source will produce and nobody should trust. Compute it, then withhold
      // it, so the row can still explain itself.
      final comparable = e.canBePricedPer(_outputUnit);
      final calc = e.calculate(outputY: _outputUnit);
      priced.add(PricedEntry(
        entry: e,
        calc: calc,
        perUnit: comparable ? calc.pencePerOutputY : null,
        comparable: comparable,
      ));
    }
    if (_estimating) {
      _estimate(priced);
      _estimateCount = priced.where((p) => p.estimate != null).length;
    } else {
      _estimateCount = 0;
    }

    final sortKey = sortColumn?.sortKey;
    if (sortKey != null) priced.sort((a, b) => _compare(sortKey, a, b));

    _cacheKey = key;
    _matchCount = priced.length;
    _stats = PriceStats.from([
      for (final p in priced)
        if (p.perUnit != null) p.perUnit!,
    ]);
    _statsWithEstimates = _estimating
        ? PriceStats.from([
            for (final p in priced)
              if (p.perUnit != null)
                p.perUnit!
              else if (p.estimate != null)
                p.estimate!.value,
          ])
        : null;
    _cached = _group(priced, prefs.groupBy);
    return _cached;
  }

  /// Fills in a guess wherever the source has no price, from the prices it
  /// does have for the same kind of thing.
  ///
  /// Trends are fitted at all three levels of the category tree and the
  /// deepest one that has enough years wins: wheat is estimated from wheat if
  /// wheat allows it, from grain if not, and from food only as a last resort.
  /// A broader basis is a weaker claim, which is why the estimate says which
  /// one it used.
  ///
  /// Entries the chosen unit cannot express are left alone — no line through
  /// prices per kilogram has anything to say about a day's labour.
  void _estimate(List<PricedEntry> priced) {
    final observations = <String, List<(int, double)>>{};
    void observe(String? key, int year, double value) {
      if (key == null) return;
      observations.putIfAbsent(key, () => []).add((year, value));
    }

    for (final p in priced) {
      final value = p.perUnit;
      final year = p.entry.year;
      if (value == null || year == null) continue;
      observe(p.entry.specific, year, value);
      observe(p.entry.subcategory, year, value);
      observe(p.entry.category, year, value);
    }

    final trends = <String, Trend?>{};
    Trend? trendFor(String? key, String basis) {
      if (key == null) return null;
      return trends.putIfAbsent(
          key, () => fitTrend(observations[key] ?? const [], basis: basis));
    }

    for (var i = 0; i < priced.length; i++) {
      final p = priced[i];
      final year = p.entry.year;
      if (p.perUnit != null || year == null || !p.comparable) continue;

      final trend = trendFor(p.entry.specific, p.entry.categoryLabel) ??
          trendFor(p.entry.subcategory,
              '${p.entry.category ?? '?'} / ${p.entry.subcategory}') ??
          trendFor(p.entry.category, p.entry.category ?? '?');
      final value = trend?.at(year);
      if (trend == null || value == null) continue;

      priced[i] = PricedEntry(
        entry: p.entry,
        calc: p.calc,
        perUnit: null,
        comparable: p.comparable,
        estimate: TrendEstimate(
          value: value,
          trend: trend,
          extrapolated: trend.isExtrapolated(year),
        ),
      );
    }
  }

  /// Gathers rows under headings, keeping the reader's sort order inside each
  /// group and ordering the groups by where they first appear.
  List<EntryGroup> _group(List<PricedEntry> rows, GroupBy by) {
    if (by == GroupBy.none) {
      return [_makeGroup('', rows)];
    }
    final buckets = <String, List<PricedEntry>>{};
    for (final row in rows) {
      buckets.putIfAbsent(_labelFor(row.entry, by), () => []).add(row);
    }
    return [
      for (final entry in buckets.entries) _makeGroup(entry.key, entry.value)
    ];
  }

  String _labelFor(PriceEntry e, GroupBy by) => switch (by) {
        GroupBy.none => '',
        GroupBy.year => e.year?.toString() ?? 'Undated',
        GroupBy.county => e.county ?? 'No county recorded',
        GroupBy.category => e.category ?? 'Uncategorised',
        GroupBy.dimension => switch (e.primaryMeasure?.dimension) {
            null => 'Kind of measure not yet classified',
            final d => 'Measured by $d',
          },
      };

  /// Builds a group and its median price per the chosen unit.
  ///
  /// Median, not mean: within a broad group the source mixes saffron with
  /// barley, and one entry priced per gram of spice would drag a mean into
  /// nonsense. Entries with no computable price are excluded from the sample
  /// rather than counted as zero, and the header says how many that left.
  EntryGroup _makeGroup(String label, List<PricedEntry> rows) {
    final values = [
      for (final r in rows)
        if (r.perUnit != null) r.perUnit!
    ]..sort();
    double? median;
    if (values.isNotEmpty) {
      final mid = values.length ~/ 2;
      median = values.length.isOdd
          ? values[mid]
          : (values[mid - 1] + values[mid]) / 2;
    }
    return EntryGroup(
      label: label,
      rows: rows,
      median: median,
      pricedCount: values.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.active
        ? context.watch<AppController>()
        : context.read<AppController>();
    final prefs = widget.active
        ? context.watch<ViewPreferences>()
        : context.read<ViewPreferences>();
    final repo = app.repository;
    final (minYear, maxYear) = repo.yearRange;

    _filters = _filters.years == null
        ? _filters.copyWith(
            years: RangeValues(minYear.toDouble(), maxYear.toDouble()))
        : _filters;

    final outputUnits = repo.outputUnitChoices;
    _outputUnit ??= _defaultOutputUnit(outputUnits);

    final size = MediaQuery.sizeOf(context);
    final compact = Breakpoints.isCompact(size.width);
    final short = Breakpoints.isShort(size.height);
    final narrow = Breakpoints.isNarrow(size.width);
    final unitName = _outputUnit?.name ?? 'unit';
    final columns = columnsFor(prefs.detailLevel, unitName);

    // The sorted column can vanish when the detail level narrows — sort by
    // Workers, drop to Basics, and there is nothing left to sort by.
    final sortColumn = columns
        .where((c) => c.id == _sortColumnId && c.sortKey != null)
        .firstOrNull;
    final groups = _results(app, prefs, sortColumn);

    return Column(
      // Stretch, not the default centre. The filter bar sizes to its widest
      // row, so centred it drifted left and right as the facet panel opened
      // and closed, and never lined up with the table beneath it.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          filters: _filters,
          onFiltersChanged: (f) => setState(() => _filters = f),
          counties: repo.counties.map((c) => c.label).toList(),
          categories: repo.categories.map((c) => c.name).toList(),
          outputUnits: outputUnits,
          outputUnit: _outputUnit,
          onOutputUnitChanged: (v) => setState(() => _outputUnit = v),
          minYear: minYear,
          maxYear: maxYear,
          resultCount: _matchCount,
          totalCount: app.entries.length,
          undatedTotal: app.entries.where((e) => e.year == null).length,
          estimating: _estimating,
          onEstimatingChanged: (v) => setState(() => _estimating = v),
          estimateCount: _estimateCount,
          dense: short,
          stats: _stats,
          statsWithEstimates: _statsWithEstimates,
          brief: narrow,
        ),
        Expanded(
          child: _matchCount == 0
              ? _NothingFound(
                  onClear: () => setState(() => _filters = FilterState(
                        years: RangeValues(
                            minYear.toDouble(), maxYear.toDouble()),
                      )),
                )
              : compact
                  ? _CompactList(
                      groups: groups,
                      unitName: unitName,
                      level: prefs.detailLevel,
                      showHeadings: prefs.groupBy != GroupBy.none,
                    )
                  : EntryTable(
                      groups: groups,
                      columns: columns,
                      rowHeight: prefs.density.rowHeight,
                      sortColumnId: sortColumn?.id,
                      ascending: _ascending,
                      onSort: _toggleSort,
                      onOpen: (e) => openEntryEditor(context, e),
                      unitName: unitName,
                      showGroupHeaders: prefs.groupBy != GroupBy.none,
                    ),
        ),
      ],
    );
  }

  MetricItem? _defaultOutputUnit(List<MetricItem> units) {
    if (units.isEmpty) return null;
    for (final name in ['Kilograms', 'Grams', 'Litres']) {
      for (final u in units) {
        if (u.name == name) return u;
      }
    }
    return units.first;
  }
}

/// What the table shows when every row has been filtered away.
///
/// A bare line of text left the reader to work out that they were looking at
/// their own filters rather than at the end of the database, and to find the
/// way back themselves.
class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_outlined, size: 40, color: scheme.outline),
          const SizedBox(height: Spacing.md),
          Text('Nothing matches these filters',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          SizedBox(
            width: 340,
            child: Text(
              'The records are still there — this combination of filters is '
              'what has nothing behind it.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton.tonalIcon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
            label: const Text('Clear the filters'),
          ),
        ],
      ),
    );
  }
}

/// The narrow-screen shape of the same result.
///
/// A table with twenty-six columns is not a phone layout, so this shows the
/// same rows as cards. The detail level still applies: it decides how much of
/// each entry the card carries, rather than being ignored on small screens.
class _CompactList extends StatelessWidget {
  const _CompactList({
    required this.groups,
    required this.unitName,
    required this.level,
    required this.showHeadings,
  });

  final List<EntryGroup> groups;
  final String unitName;
  final DetailLevel level;
  final bool showHeadings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        for (final group in groups) ...[
          if (showHeadings)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.lg, Spacing.md, Spacing.sm),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '${group.label} · ${group.rows.length} '
                  '${group.rows.length == 1 ? 'entry' : 'entries'}'
                  '${group.median == null ? '' : ' · median '
                      '${formatPence(group.median)} pence per $unitName'}',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
            sliver: SliverList.separated(
              itemCount: group.rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
              itemBuilder: (context, i) =>
                  _EntryCard(priced: group.rows[i], unitName: unitName, level: level),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Spacing.md)),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.priced,
    required this.unitName,
    required this.level,
  });

  final PricedEntry priced;
  final String unitName;
  final DetailLevel level;

  @override
  Widget build(BuildContext context) {
    final e = priced.entry;
    final reason = missingPerUnitReason(priced, unitName);
    final lines = <String>[
      '${e.year ?? 'Undated'} · ${e.placeLabel}',
      priced.perUnit == null
          ? (reason ?? 'No price per $unitName')
          : '${formatPence(priced.perUnit)} pence per $unitName',
      if (level.atLeastDetailed) e.quantityLabel,
      if (level.isEverything && e.statusInfo != null) e.statusInfo!,
      if (level.isEverything && e.sourceCitation != null)
        '${e.sourceCitation}${e.page == null ? '' : ', p. ${e.page}'}',
    ];

    return Card(
      child: ListTile(
        title: Text('${e.categoryLabel} — ${e.priceLabel}'),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 2,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openEntryEditor(context, e),
      ),
    );
  }
}
