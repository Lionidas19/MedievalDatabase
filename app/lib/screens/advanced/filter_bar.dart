import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../services/statistics.dart';
import '../../state/view_preferences.dart';
import '../../theme.dart';
import '../../widgets/filterable_dropdown.dart';
import '../simple/facets.dart';
import '../../widgets/info_dot.dart';
import '../tour/tour.dart';

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

  /// The free-text half of [matches], on its own.
  ///
  /// Facet counting needs the filters that are *not* facet axes applied
  /// first, then lets `countFacets` handle county, category and the years.
  bool passesSearch(PriceEntry e) {
    final q = search.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      e.locality, e.county, e.category, e.subcategory, e.specific,
      e.statusInfo, e.information, e.sourceCitation, e.food,
    ].where((s) => s != null).join(' ').toLowerCase();
    return hay.contains(q);
  }

  bool matches(PriceEntry e) {
    if (!passesSearch(e)) return false;
    if (!passesDate(e)) return false;
    // One option covers every spelling of a county; see [bareCountyName].
    final c = e.county;
    if (county != null && (c == null || bareCountyName(c) != county)) {
      return false;
    }
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
    required this.compact,
    required this.entries,
    required this.onNewEntry,
    required this.stats,
    required this.statsWithEstimates,
    required this.brief,
    required this.onReset,
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
  /// Opens a blank record for editing.
  ///
  /// It lives beside the detail chips rather than in the app bar, and only at
  /// Everything, which is where he asked for it: a button offering to create
  /// records above a table somebody came to read is how people end up editing
  /// by accident, and gating it on the level a reader has to choose puts it
  /// behind a deliberate act.
  final VoidCallback onNewEntry;

  /// Every entry in the database, for counting what each option would find.
  ///
  /// The bar needs the records themselves, not just how many survived: a
  /// dropdown can only strike out an option by asking what choosing it would
  /// return.
  final List<PriceEntry> entries;

  /// Set on a phone, where the toolbar was taking most of the page.
  ///
  /// At 412x870 the six controls stacked into five rows and the figures panel
  /// sat under them, leaving about two records visible above the bottom
  /// navigation. A toolbar that large is not a toolbar, it is the screen.
  ///
  /// So on a phone the bar is one row: the search box, and a Filters button
  /// that opens everything else. Price per, Group, Estimates and Reset move
  /// inside that panel, where they are still one tap away and cost nothing
  /// while they are not in use. The figures stay out, on one line, because
  /// they are the answer rather than a control.
  final bool compact;

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

  /// Put the whole question back to how the page opens.
  ///
  /// Distinct from "Clear all", which only appears once filters are active
  /// and only empties those. A reader who has changed the unit into something
  /// unanswerable has not set a filter at all, so that button is not even on
  /// screen for them. This one always is.
  final VoidCallback onReset;

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

  /// What each option would still find, memoised.
  ///
  /// `countFacets` walks every entry, and this bar rebuilds on every
  /// keystroke in the search box, so the answer is cached against the filters
  /// that can change it. Search text and the dated/undated choice are not
  /// facets `countFacets` models, so they are applied first and it counts
  /// over what is left; county, category and the year range are the axes it
  /// takes care of itself.
  String? _facetKey;
  FacetCounts _facetCounts = FacetCounts.empty;

  FacetCounts _countFacets() {
    final years = _f.years ??
        RangeValues(widget.minYear.toDouble(), widget.maxYear.toDouble());
    final key = [
      widget.entries.length,
      _f.search,
      _f.county,
      _f.category,
      _f.dateFilter.name,
      years.start,
      years.end,
      // The chosen unit decides which options can produce a figure.
      widget.outputUnit?.id,
    ].join('|');
    if (key == _facetKey) return _facetCounts;

    final searched = widget.entries
        .where((e) => _f.passesDate(e) && _f.passesSearch(e))
        .toList();
    _facetCounts = countFacets(
      searched,
      FacetQuery(
        startYear: years.start,
        endYear: years.end,
        county: _f.county,
        category: _f.category,
        unitDimension: widget.outputUnit?.dimension,
      ),
    );
    _facetKey = key;
    return _facetCounts;
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
          if (widget.compact) ...[
            const SizedBox(height: Spacing.sm),
            TourTarget(stop: TourStop.figures, child: _figures(context)),
          ],
          if (!widget.dense && !widget.compact) ...[
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
    // One row on a phone: everything the reader is not using right now is
    // behind the Filters button, which says how much of it is in play.
    if (widget.compact) {
      return Row(
        children: [
          Expanded(
            child: TourTarget(
              stop: TourStop.search,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 20),
                  hintText: 'Search',
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          TourTarget(
            stop: TourStop.filters,
            child: Badge(
              // The count has to be on the button itself: with the panel
              // shut, nothing else on the screen says a filter is narrowing
              // what the reader is looking at.
              isLabelVisible: active > 0,
              label: Text('$active'),
              child: IconButton.filledTonal(
                tooltip: _expanded ? 'Hide filters' : 'Filters and options',
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                    _expanded ? Icons.expand_less : Icons.tune, size: 20),
              ),
            ),
          ),
        ],
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      children: [
        TourTarget(
          stop: TourStop.search,
          child: SizedBox(
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
        )),
        // The same typing-aware dropdown the Specifics lookup uses.
        //
        // As a bare DropdownMenu this was the single worst control in the
        // app. Clicking it put the caret wherever the pointer landed, in the
        // middle of the label, and the list did not narrow — so somebody
        // trying to type "volume" got `volumtotototototo` in the box, a menu
        // still showing everything, and no idea how to get back. Filtering
        // and select-on-focus are what fix that, and both live in the shared
        // widget.
        InfoDot(message: Explain.pricePer, label: 'Price per'),
        _pricePerField(context),
        TourTarget(
          stop: TourStop.filters,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
                _expanded ? Icons.expand_less : Icons.filter_alt_outlined,
                size: 18),
            label: Text(active == 0 ? 'Filters' : 'Filters ($active)'),
          ),
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
          _groupMenu(context, prefs: prefs),
        ],
        // Shown even when there is nothing to average.
        //
        // These used to disappear whenever the selection could not be priced,
        // and a reader who had just changed the unit saw the figures drop off
        // the screen with no explanation — the app looked broken rather than
        // unable to answer. A row of dashes says the figures exist and this
        // selection has none, which is a different and recoverable thing.
        TextButton.icon(
          onPressed: widget.onReset,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Reset'),
        ),
        InfoDot(message: Explain.reset, label: 'Reset'),
        TourTarget(stop: TourStop.figures, child: _figures(context)),
      ],
    );
  }

  /// The price summary, laid along the toolbar.
  ///
  /// Median leads and is set heavier: with a mean of 253 against a median of
  /// 0.19, leading with the mean would be leading with the wrong number.
  /// The figures, built to be noticed.
  ///
  /// They were a grey run of small text under the toolbar, and in observed
  /// testing people who had just generated them "genuinely did not recall
  /// seeing the averages at all". The researcher's words were that these
  /// should be "much more visually distinct, arguably the first thing they
  /// should see".
  ///
  /// So: a tinted panel of its own, the median set large and in the accent
  /// colour, the rest beside it in a size that still reads as a number rather
  /// than a caption. The median leads because with a mean of 253 against a
  /// median of 0.19, leading with the mean would be leading with the wrong
  /// number.
  Widget _figures(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final recorded = widget.outputUnit?.isRecordedUnit ?? false;
    final comparable = widget.outputUnit?.isComparableUnit ?? false;

    // 'NA', not the dash used everywhere else in the app.
    //
    // His words: when nothing in the selection can be priced, the figures
    // "should still show up but have NA listed next to them. This at least
    // would show that something about that information is incompatible rather
    // than it simply not showing."
    //
    // A dash is this app's mark for a value the source never recorded, and
    // that is a different statement: the records here have prices, they just
    // cannot be expressed in the unit being asked for. Keeping one mark for
    // both would blur the two.
    Widget one(String label, double? value) => Padding(
          padding: const EdgeInsets.only(right: Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: theme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4)),
              Text(
                value == null ? 'NA' : formatPence(value),
                style: theme.titleSmall?.copyWith(
                  fontFeatures: const [tabularFigures],
                  fontWeight: FontWeight.w600,
                  color: value == null ? scheme.onSurfaceVariant : null,
                ),
              ),
            ],
          ),
        );

    Widget headline(PriceStats s) => Padding(
          padding: const EdgeInsets.only(right: Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('MEDIAN',
                  style: theme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
              Text(
                s.median == null ? 'NA' : formatPence(s.median),
                style: theme.headlineSmall?.copyWith(
                  color: s.median == null
                      ? scheme.onSurfaceVariant
                      : scheme.primary,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [tabularFigures],
                ),
              ),
            ],
          ),
        );

    Widget group(PriceStats s, {String? prefix}) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (prefix != null)
              Padding(
                padding: const EdgeInsets.only(right: Spacing.sm, bottom: 2),
                child: Text(prefix,
                    style: theme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            headline(s),
            one('mean', s.mean),
            // A phone gets the median, the mean and the sample size. Five
            // figures across 380px wrap onto three lines and the panel then
            // costs more height than the records it is describing.
            if (!widget.compact) one('mode', s.mode),
            if (!widget.brief && !widget.compact) one('lowest', s.lowest),
            if (!widget.brief && !widget.compact) one('highest', s.highest),
            // `Flexible` has to be a direct child of the Row. It was inside
            // the Padding, which is a ParentDataWidget error: in a release
            // build Flutter paints a failed widget as a plain grey box, so
            // the whole toolbar and the table under it disappeared behind
            // one. It only showed on the path where nothing can be priced,
            // which is the very case this message exists to explain.
            if (s.isEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'none of these can be priced per '
                    '${widget.outputUnit?.name ?? 'that unit'}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('of ${s.count}',
                    style: theme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
          ],
        );

    final withEstimates = widget.statsWithEstimates;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: group(widget.stats,
                    prefix: withEstimates == null ? null : 'recorded'),
              ),
              InfoDot(message: Explain.figures, label: 'these figures'),
            ],
          ),
          if (withEstimates != null) group(withEstimates, prefix: 'with estimates'),
          // Priced by each entry's own measure, these figures average
          // quarters against days against stones. Each row is sound on its
          // own; a median across them is not, and saying so is the only
          // honest way to show them at all.
          // One line, so it says the shortest true thing for whichever
          // default is in use. See the fuller note in Advanced Search.
          if ((recorded || comparable) && !widget.stats.isEmpty)
            Text(
              recorded
                  ? 'across mixed measures, so compare with care'
                  : 'across weight, volume and the head, so compare with care',
              style: theme.bodySmall?.copyWith(color: scheme.error),
            ),
        ],
      ),
    );
  }

  Widget _levelRow(BuildContext context, ViewPreferences prefs) {
    return TourTarget(
      stop: TourStop.detailLevels,
      child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.md,
      runSpacing: Spacing.sm,
      children: [
        Text('Show', style: Theme.of(context).textTheme.labelLarge),
        for (final level in DetailLevel.values)
          Tooltip(
            constraints: const BoxConstraints(maxWidth: 380),
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
        _groupMenu(context, prefs: prefs),
        if (prefs.detailLevel.isEverything) ...[
          const SizedBox(width: Spacing.sm),
          OutlinedButton.icon(
            onPressed: widget.onNewEntry,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New entry'),
          ),
        ],
      ],
    ));
  }

  /// Deliberately a chip rather than one of the detail levels: those choose how
  /// much of the record to show, this one adds figures the record does not
  /// contain, and the two should not look alike.
  Widget _estimateChip(BuildContext context) {
    return Tooltip(
          constraints: const BoxConstraints(maxWidth: 380),
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

  /// The output unit. One definition, used by the bar and by the phone's
  /// filter panel, so the two can never drift apart.
  Widget _pricePerField(BuildContext context) {
    return TourTarget(
      stop: TourStop.pricePer,
      child: FilterableDropdown<MetricItem?>(
        // Wide enough for 'Default (Heads/Unit/Kilograms)', which is the
        // label the control opens on and so the one it must be able to show.
        // His phrase, kept verbatim, because it is the one he will look for.
        width: 324,
        value: widget.outputUnit,
        label: 'Price per',
        hint: 'type a unit',
        // Struck out when the records in front of the reader cannot be
        // expressed in it. This is the control people said they did not
        // understand, and the honest answer to "what does it change" is to
        // show which of the 500 units this selection can actually answer in:
        // labour counted by the day can never be priced by the metre.
        entries: facetEntries<MetricItem?>(
          context,
          options: [
            for (final u in widget.outputUnits) (u, u.menuLabel),
          ],
          available: (u) => _countFacets().canPriceIn(u?.dimension),
          selected: widget.outputUnit,
        ),
        onSelected: widget.onOutputUnitChanged,
      ),
    );
  }

  Widget _groupMenu(BuildContext context, {required ViewPreferences prefs}) {
    // Narrower where the row has to hold everything at once. The labels still
    // fit; it is the empty half of the box that goes.
    final width = widget.dense ? 168.0 : 220.0;
    return FilterableDropdown<GroupBy>(
      width: width,
      label: 'Group',
      hint: 'how to gather rows',
      value: prefs.groupBy,
      onSelected: (v) => prefs.groupBy = v,
      entries: GroupBy.values
          .map((g) => DropdownMenuEntry(value: g, label: g.label))
          .toList(),
    );
  }

  Widget _facets(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = _countFacets();
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
          // On a phone these four live here rather than on the bar. They are
          // the same widgets, so nothing about them has to be maintained
          // twice.
          if (widget.compact) ...[
            SizedBox(
              width: double.infinity,
              child: Text(
                '${widget.resultCount} of ${widget.totalCount} entries',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontFeatures: const [tabularFigures],
                ),
              ),
            ),
            _pricePerField(context),
            _groupMenu(context, prefs: context.watch<ViewPreferences>()),
            _estimateChip(context),
            TextButton.icon(
              onPressed: widget.onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset'),
            ),
          ],
          // Counted against every other filter but not against themselves,
          // which is what makes a facet a facet: choosing Cornwall should
          // still leave every county on offer, each marked with whether it
          // has anything under the rest of the filters.
          FilterableDropdown<String?>(
            width: 210,
            label: 'County',
            hint: 'type a county',
            value: _f.county,
            onSelected: (v) => widget.onFiltersChanged(v == null
                ? _f.copyWith(clearCounty: true)
                : _f.copyWith(county: v)),
            entries: facetEntries<String?>(
              context,
              anyOption: const DropdownMenuEntry(
                  value: null, label: 'Any county'),
              options: [for (final c in widget.counties) (c, c)],
              available: (c) => counts.counties.containsKey(c),
              priceable: (c) => (counts.counties[c]?.priced ?? 0) > 0,
              unitName: widget.outputUnit?.name,
              selected: _f.county,
            ),
          ),
          FilterableDropdown<String?>(
            // Wide enough for 'Agricultural Labour', which at 190 was
            // scrolled sideways in the box and read as a truncated word.
            width: 230,
            label: 'Category',
            hint: 'type a category',
            value: _f.category,
            onSelected: (v) => widget.onFiltersChanged(v == null
                ? _f.copyWith(clearCategory: true)
                : _f.copyWith(category: v)),
            entries: facetEntries<String?>(
              context,
              anyOption: const DropdownMenuEntry(
                  value: null, label: 'Any category'),
              options: [for (final c in widget.categories) (c, c)],
              available: (c) => counts.categories.containsKey(c),
              priceable: (c) => (counts.categories[c]?.priced ?? 0) > 0,
              unitName: widget.outputUnit?.name,
              selected: _f.category,
            ),
          ),
          FilterableDropdown<DateFilter>(
            width: 210,
            label: 'Dates',
            hint: 'dated, undated or both',
            value: _f.dateFilter,
            onSelected: (v) =>
                widget.onFiltersChanged(_f.copyWith(dateFilter: v)),
            entries: DateFilter.values
                .map((d) => DropdownMenuEntry(
                      value: d,
                      label: d == DateFilter.undated
                          ? '${d.label} (${widget.undatedTotal})'
                          : d.label,
                    ))
                .toList(),
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
