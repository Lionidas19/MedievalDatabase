import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../services/statistics.dart';
import '../../state/view_preferences.dart';
import '../../theme.dart';

/// Roughly a quarter of the database had no year at all when this filter was
/// written. The year slider alone cannot express "show me those", and worse,
/// it silently swallowed them — so undated entries are their own filter rather
/// than a side effect of the slider's range.
enum DateFilter { any, dated, undated }

extension DateFilterLabel on DateFilter {
  String get label => switch (this) {
        DateFilter.any => 'Dated and undated',
        DateFilter.dated => 'Dated only',
        DateFilter.undated => 'Undated only',
      };
}

/// Everything the Explorer is currently filtering by.
///
/// Gathered into one object so it can be lifted, compared and cached as a
/// unit. The table's whole result is memoised against a key built from this,
/// which only works if "the filters" is one value rather than six fields.
class FilterState {
  const FilterState({
    this.search = '',
    this.county,
    this.category,
    this.dateFilter = DateFilter.any,
    this.years,
  });

  final String search;
  final String? county;
  final String? category;
  final DateFilter dateFilter;
  final RangeValues? years;

  FilterState copyWith({
    String? search,
    String? county,
    String? category,
    DateFilter? dateFilter,
    RangeValues? years,
    bool clearCounty = false,
    bool clearCategory = false,
  }) =>
      FilterState(
        search: search ?? this.search,
        county: clearCounty ? null : (county ?? this.county),
        category: clearCategory ? null : (category ?? this.category),
        dateFilter: dateFilter ?? this.dateFilter,
        years: years ?? this.years,
      );

  bool passesDate(PriceEntry entry) {
    final year = entry.year;
    final range = years;
    switch (dateFilter) {
      case DateFilter.undated:
        return year == null;
      case DateFilter.dated:
        if (year == null) return false;
        return range == null || (year >= range.start && year <= range.end);
      case DateFilter.any:
        // The slider constrains the entries that have a year, and cannot say
        // anything about the ones that do not.
        if (year == null) return true;
        return range == null || (year >= range.start && year <= range.end);
    }
  }

  bool matches(PriceEntry e) {
    final q = search.trim().toLowerCase();
    if (q.isNotEmpty) {
      final hay = [
        e.locality, e.county, e.category, e.subcategory, e.specific,
        e.statusInfo, e.information, e.sourceCitation, e.food,
      ].where((s) => s != null).join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    if (!passesDate(e)) return false;
    if (county != null && e.county != county) return false;
    if (category != null && e.category != category) return false;
    return true;
  }

  /// Whether the full year span is selected, i.e. the slider is not filtering.
  bool yearsAreFullRange(int min, int max) =>
      years == null || (years!.start <= min && years!.end >= max);

  int activeCount(int minYear, int maxYear) => [
        search.trim().isNotEmpty,
        county != null,
        category != null,
        dateFilter != DateFilter.any,
        !yearsAreFullRange(minYear, maxYear),
      ].where((b) => b).length;
}

/// Search, facets, detail level and grouping.
///
/// The controls used to sit in one flat `Wrap`, six of them, all equally
/// prominent. They are not equally important: what the reader is looking at
/// (detail level, output unit) is a different kind of decision from what they
/// have narrowed it to, so the narrowing now folds away when it is not in use.
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.filters,
    required this.onFiltersChanged,
    required this.counties,
    required this.categories,
    required this.outputUnits,
    required this.outputUnit,
    required this.onOutputUnitChanged,
    required this.minYear,
    required this.maxYear,
    required this.resultCount,
    required this.totalCount,
    required this.undatedTotal,
    required this.estimating,
    required this.onEstimatingChanged,
    required this.estimateCount,
    required this.dense,
    required this.stats,
    required this.statsWithEstimates,
    required this.brief,
  });

  final FilterState filters;
  final ValueChanged<FilterState> onFiltersChanged;
  final List<String> counties;
  final List<String> categories;
  final List<MetricItem> outputUnits;
  final MetricItem? outputUnit;
  final ValueChanged<MetricItem?> onOutputUnitChanged;
  final int minYear;
  final int maxYear;
  final int resultCount;
  final int totalCount;
  final int undatedTotal;

  /// Whether to fill empty prices with guesses drawn from neighbouring years.
  final bool estimating;
  final ValueChanged<bool> onEstimatingChanged;

  /// How many rows currently carry one, so the button can say what it did.
  final int estimateCount;

  /// Squeeze the toolbar onto one row.
  ///
  /// Set on short screens, where the detail chips are dropped in favour of the
  /// same control in the toolbar above — it is the one thing here that is
  /// duplicated, so it is the one thing worth losing to buy back a row of
  /// records.
  final bool dense;

  /// The middle, average and commonest price across everything the filters
  /// left, in the chosen unit — sitting in the toolbar's spare room rather
  /// than on a band of their own, which cost a row of records to say the same
  /// thing.
  final PriceStats stats;

  /// The same figures counting the estimates, when estimating is on.
  final PriceStats? statsWithEstimates;

  /// Drop the extras where horizontal room is short. Never the median, mean or
  /// mode: those are the figures that were asked for.
  final bool brief;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  bool _expanded = false;
  late final TextEditingController _searchController;
  Timer? _debounce;

  FilterState get _f => widget.filters;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.filters.search);
  }

  @override
  void didUpdateWidget(FilterBar old) {
    super.didUpdateWidget(old);
    // Only follow the parent when the parent is the one that changed it —
    // "Clear all" must empty the box, but the round trip from the reader's own
    // typing must not reset the cursor mid-word.
    if (widget.filters.search != old.filters.search &&
        widget.filters.search != _searchController.text) {
      _searchController.text = widget.filters.search;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Filtering 7,800 entries per keystroke is wasted work at typing speed.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180),
        () => widget.onFiltersChanged(_f.copyWith(search: value)));
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<ViewPreferences>();
    final scheme = Theme.of(context).colorScheme;
    final active = _f.activeCount(widget.minYear, widget.maxYear);

    // On its own surface with a seam beneath it, so the controls read as one
    // toolbar sitting above the table rather than as loose parts drifting on
    // the same ground the rows are drawn on.
    final gap = widget.dense ? Spacing.sm : Spacing.md;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      padding: EdgeInsets.fromLTRB(Spacing.lg, gap, Spacing.lg, gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One Wrap rather than two rows when space is short: the controls
          // then flow together and take a single line wherever they fit.
          _topRow(context, scheme, active, prefs),
          if (!widget.dense) ...[
            SizedBox(height: gap),
            _levelRow(context, prefs),
          ],
          if (_expanded) ...[
            SizedBox(height: gap),
            _facets(context),
          ],
          if (active > 0) ...[
            const SizedBox(height: Spacing.sm),
            _activeChips(context),
          ],
        ],
      ),
    );
  }

  Widget _topRow(BuildContext context, ColorScheme scheme, int active,
      ViewPreferences prefs) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Search place, item, notes…',
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 230,
          child: DropdownMenu<MetricItem?>(
            width: 230,
            label: const Text('Price per'),
            initialSelection: widget.outputUnit,
            onSelected: widget.onOutputUnitChanged,
            dropdownMenuEntries: widget.outputUnits
                .map((u) => DropdownMenuEntry(
                      value: u,
                      label: u.dimension == null
                          ? u.name
                          : '${u.name}  (${u.dimension})',
                    ))
                .toList(),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
              _expanded ? Icons.expand_less : Icons.filter_alt_outlined,
              size: 18),
          label: Text(active == 0 ? 'Filters' : 'Filters ($active)'),
        ),
        Text(
          // 'of 7800 entries' is worth its width when there is width to
          // spare, and is the first thing to go when there is not.
          widget.dense
              ? '${widget.resultCount} / ${widget.totalCount}'
              : '${widget.resultCount} of ${widget.totalCount} entries',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [tabularFigures],
          ),
        ),
        // On a short screen these join the first row; the detail chips they
        // used to sit beside are dropped, since the toolbar above already
        // carries that choice.
        if (widget.dense) ...[
          _estimateChip(context),
          _groupMenu(context, prefs),
        ],
        if (!widget.stats.isEmpty) _figures(context),
      ],
    );
  }

  /// The price summary, laid along the toolbar.
  ///
  /// Median leads and is set heavier: with a mean of 253 against a median of
  /// 0.19, leading with the mean would be leading with the wrong number.
  Widget _figures(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;

    Widget one(String label, double? value, {bool lead = false}) => Padding(
          padding: const EdgeInsets.only(right: Spacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$label ',
                  style:
                      theme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              Text(
                formatPence(value),
                style: (lead ? theme.titleSmall : theme.bodyMedium)?.copyWith(
                  fontFeatures: const [tabularFigures],
                  fontWeight: lead ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );

    Widget group(PriceStats s, {String? prefix}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prefix != null)
              Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: Text(prefix,
                    style: theme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            one('median', s.median, lead: true),
            one('mean', s.mean),
            one('mode', s.mode),
            if (!widget.brief) one('lowest', s.lowest),
            if (!widget.brief) one('highest', s.highest),
            Text('of ${s.count}',
                style:
                    theme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        );

    final withEstimates = widget.statsWithEstimates;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(right: Spacing.md),
          height: 26,
          width: 1,
          color: scheme.outlineVariant,
        ),
        Tooltip(
          message: withEstimates == null
              ? 'Across every entry these filters left that the source can '
                  'price, in the unit chosen at Price per.'
              : 'The upper figures count only prices the source records. The '
                  'lower ones also count the estimates, which are guesses '
                  'fitted from neighbouring years.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              group(widget.stats, prefix: withEstimates == null ? null : 'recorded'),
              if (withEstimates != null)
                group(withEstimates, prefix: 'with estimates'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _levelRow(BuildContext context, ViewPreferences prefs) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      children: [
        Text('Show', style: Theme.of(context).textTheme.labelLarge),
        for (final level in DetailLevel.values)
          Tooltip(
            message: level.description,
            child: ChoiceChip(
              label: Text(level.label),
              selected: prefs.detailLevel == level,
              showCheckmark: false,
              onSelected: (_) => prefs.detailLevel = level,
            ),
          ),
        const SizedBox(width: Spacing.sm),
        _estimateChip(context),
        const SizedBox(width: Spacing.sm),
        _groupMenu(context, prefs),
      ],
    );
  }

  /// Deliberately a chip rather than one of the detail levels: those choose how
  /// much of the record to show, this one adds figures the record does not
  /// contain, and the two should not look alike.
  Widget _estimateChip(BuildContext context) {
    return Tooltip(
          message: widget.estimating
              ? 'Empty prices are filled with a guess from the trend across '
                  'neighbouring years, shown in italics with a tilde. No '
                  'average or median includes them.'
              : 'Fill empty prices with a guess drawn from the trend across '
                  'neighbouring years for the same kind of goods. Estimates '
                  'are marked, and never counted in any average.',
          child: FilterChip(
            avatar: Icon(
              widget.estimating ? Icons.timeline : Icons.timeline_outlined,
              size: 17,
            ),
            label: Text(widget.estimating && widget.estimateCount > 0
                ? 'Estimates (${widget.estimateCount})'
                : widget.dense
                    ? 'Estimate'
                    : 'Estimate gaps'),
            selected: widget.estimating,
            onSelected: widget.onEstimatingChanged,
          ),
        );
  }

  Widget _groupMenu(BuildContext context, ViewPreferences prefs) {
    // Narrower where the row has to hold everything at once. The labels still
    // fit; it is the empty half of the box that goes.
    final width = widget.dense ? 168.0 : 220.0;
    return SizedBox(
      width: width,
      child: DropdownMenu<GroupBy>(
        width: width,
        label: const Text('Group'),
        initialSelection: prefs.groupBy,
        onSelected: (v) => prefs.groupBy = v ?? GroupBy.none,
        dropdownMenuEntries: GroupBy.values
            .map((g) => DropdownMenuEntry(value: g, label: g.label))
            .toList(),
      ),
    );
  }

  Widget _facets(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final years = _f.years ??
        RangeValues(widget.minYear.toDouble(), widget.maxYear.toDouble());

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Spacing.md,
        runSpacing: Spacing.md,
        children: [
          SizedBox(
            width: 210,
            child: DropdownMenu<String?>(
              width: 210,
              label: const Text('County'),
              initialSelection: _f.county,
              onSelected: (v) => widget.onFiltersChanged(
                  v == null ? _f.copyWith(clearCounty: true) : _f.copyWith(county: v)),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'Any county'),
                ...widget.counties
                    .map((c) => DropdownMenuEntry(value: c, label: c)),
              ],
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownMenu<String?>(
              width: 190,
              label: const Text('Category'),
              initialSelection: _f.category,
              onSelected: (v) => widget.onFiltersChanged(v == null
                  ? _f.copyWith(clearCategory: true)
                  : _f.copyWith(category: v)),
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'Any category'),
                ...widget.categories
                    .map((c) => DropdownMenuEntry(value: c, label: c)),
              ],
            ),
          ),
          SizedBox(
            width: 210,
            child: DropdownMenu<DateFilter>(
              width: 210,
              label: const Text('Dates'),
              initialSelection: _f.dateFilter,
              onSelected: (v) => widget.onFiltersChanged(
                  _f.copyWith(dateFilter: v ?? DateFilter.any)),
              dropdownMenuEntries: DateFilter.values
                  .map((d) => DropdownMenuEntry(
                        value: d,
                        label: d == DateFilter.undated
                            ? '${d.label} (${widget.undatedTotal})'
                            : d.label,
                      ))
                  .toList(),
            ),
          ),
          SizedBox(
            width: 280,
            child: Row(
              children: [
                Text('${years.start.round()}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFeatures: const [tabularFigures])),
                Expanded(
                  child: RangeSlider(
                    min: widget.minYear.toDouble(),
                    max: widget.maxYear.toDouble(),
                    values: years,
                    // The slider can only speak about entries that have a
                    // year, so it is meaningless when showing only undated.
                    onChanged: _f.dateFilter == DateFilter.undated
                        ? null
                        : (r) => widget.onFiltersChanged(_f.copyWith(years: r)),
                  ),
                ),
                Text('${years.end.round()}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFeatures: const [tabularFigures])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeChips(BuildContext context) {
    final years = _f.years;
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_f.search.trim().isNotEmpty)
          _chip(context, 'matching "${_f.search.trim()}"',
              () => widget.onFiltersChanged(_f.copyWith(search: ''))),
        if (_f.county != null)
          _chip(context, _f.county!,
              () => widget.onFiltersChanged(_f.copyWith(clearCounty: true))),
        if (_f.category != null)
          _chip(context, _f.category!,
              () => widget.onFiltersChanged(_f.copyWith(clearCategory: true))),
        if (_f.dateFilter != DateFilter.any)
          _chip(context, _f.dateFilter.label,
              () => widget.onFiltersChanged(
                  _f.copyWith(dateFilter: DateFilter.any))),
        if (years != null && !_f.yearsAreFullRange(widget.minYear, widget.maxYear))
          _chip(
            context,
            '${years.start.round()}–${years.end.round()}',
            () => widget.onFiltersChanged(_f.copyWith(
                years: RangeValues(
                    widget.minYear.toDouble(), widget.maxYear.toDouble()))),
          ),
        TextButton(
          onPressed: () => widget.onFiltersChanged(FilterState(
            years: RangeValues(
                widget.minYear.toDouble(), widget.maxYear.toDouble()),
          )),
          child: const Text('Clear all'),
        ),
        if (widget.undatedTotal > 0 && _f.dateFilter == DateFilter.any)
          Text(
            'including ${widget.undatedTotal} undated',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, VoidCallback onDeleted) =>
      InputChip(
        label: Text(label),
        onDeleted: onDeleted,
        deleteIcon: const Icon(Icons.close, size: 16),
      );
}
