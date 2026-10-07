import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/database_repository.dart';
import '../../services/pricing.dart';
import '../../state/app_controller.dart';
import '../../state/view_preferences.dart';
import '../../theme.dart';
import '../../widgets/autocomplete_field.dart';
import '../../widgets/filterable_dropdown.dart';
import '../../widgets/info_dot.dart';
import '../tour/tour.dart';
import '../../widgets/price_trend_chart.dart';
import 'facets.dart';
import '../advanced/advanced_view.dart' show openEntryEditor;

/// How much of the question the reader wants to fill in is [DetailLevel],
/// shared with the Explorer and the entry editor.
///
/// The researcher sketched two versions of this screen and named them
/// "CACTUS VERSION" and "NOT AS CACTUS". Cactus asks the fewest questions it
/// can: a country, a span of years, one item. The other adds region and
/// locality, the full category chain, and a time period. Same question, same
/// answer — only the number of decisions differs. That is exactly the
/// distinction the shared setting draws, so this screen no longer keeps its
/// own: a reader who asked for everything in the table has not asked to be
/// given the short form of the question here.

/// A row of single-choice chips.
///
/// SegmentedButton was the obvious control here and it kept clipping its own
/// labels — 'Median' and 'Detailed' both lost their last letter regardless of
/// padding, because it sizes every segment alike and then crops rather than
/// growing. Chips size to their content, which is all this needs to do.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(labelOf(v)),
            selected: v == selected,
            showCheckmark: false,
            onSelected: (_) => onSelected(v),
          ),
      ],
    );
  }
}

/// Everything a lookup asks for, gathered so the result card takes one thing.
class _Query {
  const _Query({
    required this.category,
    required this.subcategory,
    required this.specific,
    required this.years,
    required this.county,
    required this.locality,
    required this.timePeriod,
    required this.outputUnit,
    required this.kind,
    required this.showEntries,
  });

  final CategoryOption? category;
  final SubcategoryOption? subcategory;
  final SpecificOption? specific;
  final RangeValues years;
  final String? county;
  final String? locality;
  final String? timePeriod;
  final MetricItem? outputUnit;
  final AverageKind kind;
  final bool showEntries;

  bool matches(PriceEntry e) {
    if (category != null && e.category != category!.name) return false;
    if (subcategory != null && e.subcategory != subcategory!.name) return false;
    if (specific != null && e.specific != specific!.name) return false;
    final y = e.year;
    if (y == null || y < years.start || y > years.end) return false;
    final ec = e.county;
    if (county != null && (ec == null || bareCountyName(ec) != county)) {
      return false;
    }
    if (locality != null && e.locality != locality) return false;
    if (timePeriod != null && e.timePeriodName != timePeriod) return false;
    return true;
  }

  String get label => [
    category?.name,
    subcategory?.name,
    specific?.name,
  ].where((s) => s != null).join(' / ');

  String get whereLabel {
    if (locality != null) return ' in $locality';
    if (county != null) return ' in $county';
    return '';
  }
}

class SimpleView extends StatefulWidget {
  const SimpleView({super.key, this.active = true});

  /// Whether this is the view currently on screen.
  ///
  /// Only the visible view subscribes to settings and data. An off-screen view
  /// that listens is rebuilt on every change nobody asked it to react to,
  /// which is work spent on pixels that do not exist. It picks up whatever
  /// changed the moment it is shown again, because switching views rebuilds
  /// both of them anyway.
  final bool active;

  @override
  State<SimpleView> createState() => _SimpleViewState();
}

/// One width for every control on the question, so the sentence reads as a
/// row of like things rather than a jumble of boxes.
/// 240 rather than something tighter because the unit names carry their kind
/// with them — 'Kilograms  (mass)' was losing its last letters at 200.
const _fieldWidth = 240.0;

class _SimpleViewState extends State<SimpleView> {
  CategoryOption? _category;
  SubcategoryOption? _subcategory;
  SpecificOption? _specific;
  RangeValues? _yearRange;
  LookupItem? _county;
  String? _locality;

  /// What is actually in the locality box, which is not the same as the filter:
  /// half-typed text filters by nothing at all.
  String _localityText = '';
  String? _timePeriod;
  MetricItem? _outputUnit;

  // Median by default, not mean. The source's measures mix dimensions —
  // 'Heads/Units' is a count, 'Tun, Wine' is litres, 'Little Pound, Spices' is
  // grams — so a broad selection can contain values many thousands of times
  // apart and a mean says almost nothing. Food across the whole range has a
  // median of 0.17 pence/kg and a mean of 366.
  AverageKind _kind = AverageKind.median;
  bool _showEntries = false;
  bool _generated = false;

  /// Where the answer appears, so the screen can be taken to it.
  ///
  /// Generate results used to change something a long way below the fold, and
  /// with no visible scrollbar the button looked broken: people pressed it,
  /// saw nothing move, and pressed it again.
  final _resultKey = GlobalKey();

  /// What is typed in the item search, which is not the same as what it
  /// resolved to — a half-typed word names nothing yet.
  String _itemSearch = '';

  /// Puts the question back to the one the screen opens with.
  ///
  /// Every field at once, rather than one clear per control: the reason to
  /// reach for this is having narrowed too far and wanting to start over, and
  /// hunting down six separate crosses is not starting over.
  void _clearAll(int minYear, int maxYear) {
    setState(() {
      _category = null;
      _subcategory = null;
      _specific = null;
      _county = null;
      _locality = null;
      _localityText = '';
      _itemSearch = '';
      _timePeriod = null;
      _yearRange = RangeValues(minYear.toDouble(), maxYear.toDouble());
      _generated = false;
    });
  }

  // Facet counts, kept until a filter or the data moves. The locality box
  // calls setState on every keystroke, and this walks all 7,800 entries.
  String? _facetKey;
  FacetCounts _facets = FacetCounts.empty;

  FacetCounts _countFacets(AppController app) {
    final key = [
      app.revision,
      _yearRange?.start,
      _yearRange?.end,
      _county?.label,
      _locality,
      _timePeriod,
      _category?.name,
      _subcategory?.name,
      _specific?.name,
    ].join('|');
    if (key == _facetKey) return _facets;
    _facetKey = key;
    return _facets = countFacets(
      app.entries,
      FacetQuery(
        startYear: _yearRange?.start ?? 0,
        endYear: _yearRange?.end ?? 9999,
        county: _county?.label,
        locality: _locality,
        timePeriod: _timePeriod,
        category: _category?.name,
        subcategory: _subcategory?.name,
        specific: _specific?.name,
      ),
    );
  }

  /// Options for one dropdown, with the dead ends sent to the bottom.
  ///
  /// An option nothing matches is kept rather than hidden — its absence would
  /// be a puzzle, where a struck-through name is an answer: the records hold
  /// none of that, here. The current selection always stays selectable, or
  /// narrowing a filter could strand the reader on a value they cannot leave.
  /// Kept as a wrapper so the six call sites below read the same as before.
  /// The logic moved to `widgets/filterable_dropdown.dart` when Data Display
  /// needed it too.
  List<DropdownMenuEntry<T>> _facetEntries<T>({
    required List<(T, String)> options,
    required bool Function(T) available,
    required T? selected,
    DropdownMenuEntry<T>? anyOption,
  }) =>
      facetEntries<T>(
        context,
        options: options,
        available: available,
        selected: selected,
        anyOption: anyOption,
      );

  @override
  Widget build(BuildContext context) {
    final app = widget.active
        ? context.watch<AppController>()
        : context.read<AppController>();
    final prefs = widget.active
        ? context.watch<ViewPreferences>()
        : context.read<ViewPreferences>();
    final level = prefs.detailLevel;
    // Basics asks the fewest questions it can. Both fuller levels ask them
    // all; what "Everything" adds is in the answer, not the question.
    final isSimple = level == DetailLevel.basics;
    // On a laptop the whole question plus its answer will not fit at once, and
    // the Generate button was falling below the fold. Tightening the rhythm
    // buys back enough for the button to sit on screen with the form.
    final short = Breakpoints.isShort(MediaQuery.sizeOf(context).height);
    final gap = short ? 8.0 : 12.0;
    final repo = app.repository;
    final (minYear, maxYear) = repo.yearRange;
    _yearRange ??= RangeValues(minYear.toDouble(), maxYear.toDouble());

    final outputUnits = [
      MetricItem.comparableUnit,
      MetricItem.recordedUnit,
      ...repo.outputUnitChoices,
    ];
    _outputUnit ??= _defaultOutputUnit(outputUnits);

    final categories = repo.categories;
    final subcategories = _category == null
        ? <SubcategoryOption>[]
        : repo.subcategoriesOf(_category!.id);
    final specifics = _subcategory == null
        ? <SpecificOption>[]
        : repo.specificsOf(_subcategory!.id);

    final countries = repo.countries;
    final counties = repo.filterCounties;
    final facets = _countFacets(app);
    final allLocalities = repo
        .localitiesInCounty(_county?.id)
        .map((l) => l.label)
        .toList();
    // Only localities that would find something, unless nothing would.
    final withEntries = allLocalities
        .where(facets.localities.containsKey)
        .toList();
    final localityNames = withEntries.isEmpty ? allLocalities : withEntries;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(short ? Spacing.md : Spacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: EdgeInsets.all(short ? Spacing.lg : Spacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.eco,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Advanced Search',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      // The level's description is the first thing to go when
                      // the screen is short: the chips below say the same in
                      // one word each, and the room buys the Generate button a
                      // place above the fold.
                      if (!short) ...[
                        const SizedBox(height: 4),
                        Text(
                          level.description,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      // Its own row rather than trailing the title: sharing a
                      // Row with a Spacer left the chips a hair too little
                      // width and clipped their last letter.
                      _ChoiceRow<DetailLevel>(
                        values: DetailLevel.values,
                        selected: level,
                        labelOf: (d) => d.label,
                        onSelected: (d) => prefs.detailLevel = d,
                      ),
                      SizedBox(height: short ? Spacing.md : 20),

                      TourTarget(
                        stop: TourStop.searchForm,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                      // --- where ---
                      _sentenceRow([
                        const Text('In'),
                        if (countries.length == 1)
                          _fixedValue(context, countries.first.label)
                        else
                          _dropdown<String?>(
                            width: _fieldWidth,
                            value: null,
                            hint: 'any country',
                            entries: [
                              const DropdownMenuEntry(
                                value: null,
                                label: 'Any country',
                              ),
                              ...countries.map(
                                (c) => DropdownMenuEntry(
                                  value: c.label,
                                  label: c.label,
                                ),
                              ),
                            ],
                            onSelected: (_) {},
                          ),
                        if (!isSimple) ...[
                          _dropdown<LookupItem?>(
                            width: _fieldWidth,
                            value: _county,
                            hint: 'any region',
                            entries: _facetEntries<LookupItem?>(
                              anyOption: const DropdownMenuEntry(
                                value: null,
                                label: 'Any region',
                              ),
                              options: [for (final c in counties) (c, c.label)],
                              available: (c) =>
                                  facets.counties.containsKey(c?.label),
                              selected: _county,
                            ),
                            onSelected: (v) => setState(() {
                              _county = v;
                              _locality = null;
                              _localityText = '';
                            }),
                          ),
                          // Typed, not picked from a list.
                          //
                          // A DropdownMenu builds every one of its entries up
                          // front, and there are 789 localities: opening this
                          // screen locked the app for five seconds. It was
                          // also unusable — nobody scrolls to 'Wyllindone'.
                          // Keyed to the county so choosing one clears
                          // whatever locality was typed for the last.
                          SizedBox(
                            width: _fieldWidth,
                            child: AutocompleteField(
                              key: ValueKey('locality-${_county?.id}'),
                              label: 'Locality',
                              initialValue: _locality ?? '',
                              suggestions: localityNames,
                              helperText:
                                  _locality == null &&
                                      _localityText.trim().isNotEmpty
                                  ? 'No locality of that name'
                                  : 'Blank means any',
                              onChanged: (text) => setState(() {
                                _localityText = text;
                                // Only an exact name filters. Half-typed text
                                // would silently match nothing and look like
                                // an empty database.
                                _locality = localityNames.contains(text)
                                    ? text
                                    : null;
                              }),
                            ),
                          ),
                        ],
                      ]),
                      SizedBox(height: gap),

                      // --- when ---
                      _sentenceRow([
                        const Text('Between the years'),
                        _yearField(isStart: true, min: minYear, max: maxYear),
                        const Text('and'),
                        _yearField(isStart: false, min: minYear, max: maxYear),
                        InfoDot(
                            message: Explain.yearRange, label: 'the years'),
                        if (!isSimple) ...[
                          const Text('at'),
                          _dropdown<String?>(
                            width: _fieldWidth,
                            value: _timePeriod,
                            hint: 'any time of year',
                            entries: _facetEntries<String?>(
                              anyOption: const DropdownMenuEntry(
                                value: null,
                                label: 'Any time of year',
                              ),
                              options: [
                                for (final t in repo.timePeriods)
                                  (t.label, t.label),
                              ],
                              available: (t) =>
                                  facets.timePeriods.containsKey(t),
                              selected: _timePeriod,
                            ),
                            onSelected: (v) => setState(() => _timePeriod = v),
                          ),
                        ],
                      ]),
                      if (!isSimple)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 2),
                          child: Text(
                            'Time of year mixes months, seasons and feast days, '
                            'exactly as the records do.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      // The slider itself is not here. It sits at the top
                      // of the answer below, which is where he put it: "This
                      // would also be the perfect place to put the year
                      // slider if at all possible, so that you can very
                      // quickly slide the date around to see how that changes
                      // things." Watching a figure move while you drag only
                      // works if the figure is on the screen with the handle.
                      //
                      // The two year boxes stay here, because they are part
                      // of the sentence the form is asking you to read.

                      // --- what ---
                      //
                      // The search box comes first because it is the way in
                      // for anyone who does not already know the taxonomy:
                      // type 'wheat' and all three levels are filled in. The
                      // dropdowns stay for browsing, and follow it.
                      _sentenceRow([
                        const Text('Item:'),
                        SizedBox(
                          width: _fieldWidth,
                          child: AutocompleteField(
                            key: ValueKey(
                              'item-search-'
                              '${_category?.id}-${_subcategory?.id}-${_specific?.id}',
                            ),
                            label: 'Search all three levels',
                            initialValue: _itemSearch,
                            suggestions: _suggestionOrder(app, repo),
                            helperText: 'e.g. wheat, oxen, thatching',
                            onChanged: (text) => setState(() {
                              _itemSearch = text;
                              final match = repo.taxonomyPaths
                                  .where((t) => t.label == text)
                                  .firstOrNull;
                              if (match == null) return;
                              _category = match.category;
                              _subcategory = match.subcategory;
                              _specific = match.specific;
                            }),
                          ),
                        ),
                      ]),
                      SizedBox(height: gap),
                      _sentenceRow([
                        const Text('or pick:'),
                        _dropdown<CategoryOption?>(
                          width: _fieldWidth,
                          value: _category,
                          hint: 'category',
                          entries: _facetEntries<CategoryOption?>(
                            anyOption: const DropdownMenuEntry(
                              value: null,
                              label: 'Any category',
                            ),
                            options: [for (final c in categories) (c, c.name)],
                            available: (c) =>
                                facets.categories.containsKey(c?.name),
                            selected: _category,
                          ),
                          onSelected: (v) => setState(() {
                            _category = v;
                            _subcategory = null;
                            _specific = null;
                            _itemSearch = v?.name ?? '';
                          }),
                        ),
                        _dropdown<SubcategoryOption?>(
                          width: _fieldWidth,
                          value: _subcategory,
                          hint: 'subcategory',
                          enabled: _category != null,
                          entries: _facetEntries<SubcategoryOption?>(
                            anyOption: const DropdownMenuEntry(
                              value: null,
                              label: 'Any subcategory',
                            ),
                            options: [
                              for (final s in subcategories) (s, s.name),
                            ],
                            available: (s) =>
                                facets.subcategories.containsKey(s?.name),
                            selected: _subcategory,
                          ),
                          onSelected: (v) => setState(() {
                            _subcategory = v;
                            _specific = null;
                            _itemSearch = [
                              _category?.name,
                              v?.name,
                            ].whereType<String>().join(' / ');
                          }),
                        ),
                        if (!isSimple)
                          _dropdown<SpecificOption?>(
                            width: _fieldWidth,
                            value: _specific,
                            hint: 'specific',
                            enabled: _subcategory != null,
                            entries: _facetEntries<SpecificOption?>(
                              anyOption: const DropdownMenuEntry(
                                value: null,
                                label: 'Any specific',
                              ),
                              options: [for (final s in specifics) (s, s.name)],
                              available: (s) =>
                                  facets.specifics.containsKey(s?.name),
                              selected: _specific,
                            ),
                            onSelected: (v) => setState(() {
                              _specific = v;
                              _itemSearch = [
                                _category?.name,
                                _subcategory?.name,
                                v?.name,
                              ].whereType<String>().join(' / ');
                            }),
                          ),
                      ]),
                      SizedBox(height: gap),
                          ],
                        ),
                      ),

                      // --- in what unit ---
                      // The control this whole rewrite exists to make
                      // possible: the answer is computed per entry in
                      // whichever unit is picked, not read from a fixed
                      // column.
                      TourTarget(
                        stop: TourStop.searchUnit,
                        child: _sentenceRow([
                        const Text('returned value as pence per'),
                        _dropdown<MetricItem?>(
                          width: _fieldWidth,
                          value: _outputUnit,
                          hint: 'unit',
                          // The one the screen exists for: labour counted by
                          // the day cannot be priced per kilogram, and saying
                          // so before the question is asked beats explaining it
                          // after the answer comes back empty.
                          entries: _facetEntries<MetricItem?>(
                            options: [
                              for (final u
                                  in isSimple
                                      ? _commonUnits(outputUnits)
                                      : outputUnits)
                                (u, u.menuLabel),
                            ],
                            available: (u) => facets.canPriceIn(u?.dimension),
                            selected: _outputUnit,
                          ),
                          onSelected: (v) => setState(() => _outputUnit = v),
                        ),
                      ])),
                      if (!facets.canPriceIn(_outputUnit?.dimension))
                        Padding(
                          padding: const EdgeInsets.only(top: 6, left: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.straighten,
                                size: 15,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'These are measured by '
                                  '${facets.dimensionsInWords}, so none of '
                                  'them can be priced per '
                                  '${_outputUnit?.name ?? 'that unit'}. Pick '
                                  'one of the units that is not crossed out.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: short ? Spacing.md : 20),

                      Text(
                        'Show',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      _ChoiceRow<AverageKind>(
                        values: AverageKind.values,
                        selected: _kind,
                        labelOf: (k) => k.label,
                        onSelected: (k) => setState(() => _kind = k),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: short,
                        visualDensity: short ? VisualDensity.compact : null,
                        title: const Text('Show original data entries'),
                        value: _showEntries,
                        onChanged: (v) => setState(() => _showEntries = v),
                      ),
                      SizedBox(height: gap),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => _clearAll(minYear, maxYear),
                            icon: const Icon(
                              Icons.backspace_outlined,
                              size: 17,
                            ),
                            label: const Text('Clear'),
                          ),
                          const SizedBox(width: Spacing.sm),
                          TourTarget(
                            stop: TourStop.searchGenerate,
                            child: FilledButton.icon(
                            onPressed: _category == null
                                ? null
                                : () {
                                    setState(() => _generated = true);
                                    // After the frame, because the results do
                                    // not exist to scroll to until this
                                    // setState has been built.
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      final box = _resultKey.currentContext;
                                      if (box == null) return;
                                      Scrollable.ensureVisible(
                                        box,
                                        duration: const Duration(
                                            milliseconds: 350),
                                        curve: Curves.easeOutCubic,
                                        alignment: 0.05,
                                      );
                                    });
                                  },
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Generate results'),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_generated && _category != null) ...[
                KeyedSubtree(key: _resultKey, child: const SizedBox.shrink()),
                const SizedBox(height: 20),
                _ResultCard(
                  level: level,
                  minYear: minYear,
                  maxYear: maxYear,
                  onYearsChanged: (r) => setState(() => _yearRange = r),
                  query: _Query(
                    category: _category,
                    subcategory: _subcategory,
                    specific: isSimple ? null : _specific,
                    years: _yearRange!,
                    county: isSimple ? null : _county?.label,
                    locality: isSimple ? null : _locality,
                    timePeriod: isSimple ? null : _timePeriod,
                    outputUnit: _outputUnit,
                    kind: _kind,
                    showEntries: _showEntries,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Item suggestions, commonest first rather than alphabetical.
  ///
  /// Typing 'oats' used to offer 'Agricultural Labour / Mowing / Oats
  /// (Mowing)' before 'Food / Grain / Oats', because A sorts before F. The
  /// reader almost always wants the one the source has most of, so the list is
  /// ordered by how many entries actually sit under each path. Ties keep
  /// alphabetical order, so the list is still predictable where the counts
  /// say nothing.
  ///
  /// Counted once per data revision: it walks all 7,800 entries, and the
  /// search box rebuilds on every keystroke.
  int? _suggestionRevision;
  List<String> _suggestions = const [];

  List<String> _suggestionOrder(AppController app, DatabaseRepository repo) {
    if (_suggestionRevision == app.revision) return _suggestions;
    _suggestionRevision = app.revision;

    final uses = <String, int>{};
    void count(String? name) {
      if (name == null || name.isEmpty) return;
      uses[name] = (uses[name] ?? 0) + 1;
    }

    for (final e in app.entries) {
      count(e.category);
      count(e.subcategory);
      count(e.specific);
    }

    final paths = List<TaxonomyPath>.of(repo.taxonomyPaths);
    paths.sort((TaxonomyPath a, TaxonomyPath b) {
      final byUse = (uses[b.leaf] ?? 0).compareTo(uses[a.leaf] ?? 0);
      return byUse != 0 ? byUse : a.label.compareTo(b.label);
    });
    return _suggestions = [for (final path in paths) path.label];
  }

  /// The one answer that always exists, and the most comparable one that
  /// does.
  ///
  /// See [MetricItem.comparableUnit]. This was Kilograms, which left a reader
  /// who picked a unit the selection cannot express with an empty screen and
  /// no way back; then the recorded unit, which always answers but leaves one
  /// grain record in quarters and the next in bushels.
  MetricItem? _defaultOutputUnit(List<MetricItem> units) =>
      MetricItem.comparableUnit;


  /// A short list for the simple view. 97 output units is a research tool, not
  /// a question to put to somebody who wants the price of wheat.
  List<MetricItem> _commonUnits(List<MetricItem> units) {
    // Weights, a volume — and a count, without which a whole half of the
    // database is unanswerable here. Labour is paid by the day and stock is
    // sold by the head; offering only units of mass left those categories
    // with nothing to be priced in at all.
    const wanted = [
      'comparable unit',
      'Recorded unit',
      'Kilograms',
      'Grams',
      'Litres',
      'US Pounds',
      'Tower Pound',
      'Troy Pound',
      'Heads/Units',
    ];
    final short = [
      for (final name in wanted) ...units.where((u) => u.name == name),
    ];
    // Always include whatever is currently selected, so switching from the
    // detailed view cannot leave the dropdown showing a value it lacks.
    final current = _outputUnit;
    if (current != null && !short.contains(current)) short.insert(0, current);
    return short.isEmpty ? units.take(6).toList() : short;
  }

  Widget _fixedValue(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text),
  );

  Widget _sentenceRow(List<Widget> children) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 10,
    runSpacing: 8,
    children: children,
  );

  Widget _yearField({
    required bool isStart,
    required int min,
    required int max,
  }) {
    final value = isStart ? _yearRange!.start : _yearRange!.end;
    // A year box is never empty, so its cross puts the end of the range back
    // where the records start or stop rather than blanking the field — and it
    // only appears once that end has actually been moved, so the row is not
    // carrying two crosses that would do nothing.
    final bound = (isStart ? min : max).toDouble();
    final moved = value != bound;
    return SizedBox(
      // Same width and the same un-dense decoration as the dropdowns it sits
      // between; `isDense` made these two boxes visibly shorter than every
      // other control on the row.
      width: _fieldWidth,
      child: TextFormField(
        key: ValueKey('$isStart-${_yearRange!.start}-${_yearRange!.end}'),
        initialValue: value.round().toString(),
        keyboardType: TextInputType.number,
        // 'From' and 'to' rather than 'Year' twice: the sentence around them
        // has already said which years these are.
        decoration: InputDecoration(
          labelText: isStart ? 'From' : 'to',
          suffixIcon: moved
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Back to ${bound.round()}',
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() {
                    _yearRange = isStart
                        ? RangeValues(bound, _yearRange!.end)
                        : RangeValues(_yearRange!.start, bound);
                  }),
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        onChanged: (text) {
          final v = double.tryParse(text);
          if (v == null) return;
          setState(() {
            _yearRange = isStart
                ? RangeValues(
                    v.clamp(min.toDouble(), max.toDouble()),
                    _yearRange!.end,
                  )
                : RangeValues(
                    _yearRange!.start,
                    v.clamp(min.toDouble(), max.toDouble()),
                  );
          });
        },
      ),
    );
  }

  Widget _dropdown<T>({
    required double width,
    required T value,
    required String hint,
    required List<DropdownMenuEntry<T>> entries,
    required ValueChanged<T> onSelected,
    bool enabled = true,
  }) => FilterableDropdown<T>(
    width: width,
    value: value,
    hint: hint,
    entries: entries,
    onSelected: onSelected,
    enabled: enabled,
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.query,
    required this.level,
    required this.minYear,
    required this.maxYear,
    required this.onYearsChanged,
  });

  final _Query query;
  final DetailLevel level;

  /// The span the records cover, for the slider that heads the answer.
  final int minYear;
  final int maxYear;

  /// Moving the slider re-asks the question. Nothing has to be pressed again:
  /// the answer below is built from the range on every frame.
  final ValueChanged<RangeValues> onYearsChanged;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final matches = app.entries.where(query.matches).toList();

    // Every value is computed in the same reader-chosen unit, so averaging
    // them is meaningful. Reading a stored per-unit column instead would mix
    // quarters, kilograms and acres into one meaningless number.
    // Each entry converted by the factor for *its own* year, and only then
    // averaged. Converting the average instead would need one factor for a
    // span of years that has several, and would quietly pick one.
    final modern = app.repository.modernPoundsPerPenny;
    final modernValues = <double>[];

    final priced = <(PriceEntry, double)>[];
    var unpriced = 0;
    var wrongKind = 0;
    for (final e in matches) {
      // Counting cattle by the head and then asking their price per kilogram
      // is arithmetic the source will happily perform and nobody should
      // believe. Leave those out of the average rather than let them drag it.
      if (!e.canBePricedPer(query.outputUnit)) {
        wrongKind++;
        continue;
      }
      // One decision, made in the model. See [PriceEntry.pricedIn].
      final p = e.pricedIn(
        query.outputUnit,
        modernPoundsPerPenny: modern[e.year],
      );
      final v = p.perUnit;
      if (v == null || !v.isFinite) {
        unpriced++;
      } else {
        priced.add((e, v));
        final m = p.modern;
        if (m != null && m.isFinite) modernValues.add(m);
      }
    }
    final values = priced.map((p) => p.$2).toList()..sort();
    modernValues.sort();

    // One median per year, for the chart. Built from the same priced list so
    // the line can never disagree with the figure above it.
    final byYear = <int, List<double>>{};
    for (final (entry, value) in priced) {
      final year = entry.year;
      if (year == null) continue;
      byYear.putIfAbsent(year, () => []).add(value);
    }
    final trend = <YearPoint>[];
    for (final year in byYear.keys.toList()..sort()) {
      final v = byYear[year]!..sort();
      trend.add(YearPoint(
        year: year,
        median: v[v.length ~/ 2],
        count: v.length,
      ));
    }
    // Lower case in a sentence: "1.6 pence per comparable unit" reads as
    // English, "per Comparable unit" reads as a variable name.
    final unitName = query.outputUnit?.name ?? 'unit';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The deepest level the reader asked for, set apart from the
            // branch above it — the same emphasis the table gives the item
            // column, so an answer is recognisably about the same thing.
            _QueryLabel(query: query),
            const SizedBox(height: 4),
            Text(
              '${matches.length} matching entr${matches.length == 1 ? 'y' : 'ies'} '
              'between ${query.years.start.round()} and '
              '${query.years.end.round()}${query.whereLabel}'
              '${query.timePeriod != null ? ', ${query.timePeriod}' : ''}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            // Sweeping the range rather than typing it, and sitting with
            // the answer so the answer can be watched changing. Divisions are
            // fixed to whole years: a span of 21 years has no meaningful
            // fractional position, and a free slider lands on 1283.4.
            const SizedBox(height: Spacing.sm),
            _YearSlider(
              min: minYear,
              max: maxYear,
              values: query.years,
              onChanged: onYearsChanged,
            ),
            const SizedBox(height: 16),
            if (values.isEmpty)
              Text(
                matches.isEmpty
                    ? 'No entries match this lookup.'
                    : wrongKind == matches.length
                    ? 'None of the ${matches.length} matching entries are '
                          'measured by anything that converts to $unitName. '
                          'Try a unit of the kind these goods were actually '
                          'sold in.'
                    : 'None of the ${matches.length} matching entries can '
                          'be priced per $unitName — their quantities or '
                          'units are missing from the source.',
              )
            else if (query.kind != AverageKind.all)
              _StatTile(
                label: query.kind.label,
                value: _stat(values, query.kind),
                unitName: unitName,
                sampleSize: values.length,
                // The same statistic over the converted figures, not the
                // statistic converted: the sample spans years with different
                // factors.
                modern: modernValues.isEmpty
                    ? null
                    : _stat(modernValues, query.kind),
                modernYear: app.repository.modernMoneyYear,
              )
            else
              Text(
                '${values.length} priced entries found — see the list below.',
              ),
            if (level.isEverything && values.isNotEmpty) ...[
              const SizedBox(height: Spacing.md),
              _Spread(values: values, unitName: unitName),
            ],
            // How the price moved across the years asked for. New in response
            // to the researcher: "set a year range and it could display the
            // information over time as a line graph".
            if (trend.length >= 2) ...[
              const SizedBox(height: Spacing.lg),
              Row(
                children: [
                  Expanded(
                    child: PriceTrendChart(
                      points: trend,
                      unitName: unitName,
                    ),
                  ),
                  InfoDot(message: Explain.graph, label: 'this chart'),
                ],
              ),
            ],
            // Both defaults mix, and they do not mix equally, so they do
            // not get the same warning. Priced by each record's own measure,
            // an average adds quarters to days to stones. Priced per the
            // comparable unit, everything sold by weight is already in
            // kilograms and only the different *kinds* of thing are still
            // being added together. Saying the stronger thing in the milder
            // case would train a reader to ignore both.
            if (values.isNotEmpty &&
                (query.outputUnit?.isRecordedUnit ?? false)) ...[
              const SizedBox(height: 10),
              _note(
                context,
                'Each entry is priced by the measure the source used for it, '
                'so this average covers different measures at once. It shows '
                'the shape of the selection rather than a figure you can '
                'compare with another. Choose a single unit above for that.',
                Theme.of(context).colorScheme.error,
                Icons.straighten,
              ),
            ],
            if (values.isNotEmpty &&
                (query.outputUnit?.isComparableUnit ?? false)) ...[
              const SizedBox(height: 10),
              _note(
                context,
                'Everything sold by weight is priced per kilogram here, and '
                'everything counted is priced per head, so figures of the '
                'same kind can be compared. This average still adds the '
                'kinds together. Choose a single unit above to keep it to '
                'one.',
                Theme.of(context).colorScheme.error,
                Icons.straighten,
              ),
            ],
            if (values.isNotEmpty && _isWidelySpread(values)) ...[
              const SizedBox(height: 10),
              _note(
                context,
                'Prices here span a very wide range — the dearest is '
                '${_spreadFactor(values)} times the middle of the pack. A '
                'broad category mixes saffron with barley, so the median is '
                'far more representative than the mean. Narrow the item to '
                'compare like with like.',
                Theme.of(context).colorScheme.onSurfaceVariant,
                Icons.show_chart,
              ),
            ],
            if (wrongKind > 0) ...[
              const SizedBox(height: 10),
              _note(
                context,
                '$wrongKind of ${matches.length} entries are measured in a '
                'different kind of unit — counted by the head or the dozen, or '
                'measured by area — and cannot be expressed per $unitName. '
                'They are left out rather than converted into a number that '
                'would look real and mean nothing.',
                Theme.of(context).colorScheme.onSurfaceVariant,
                Icons.straighten,
              ),
            ],
            if (values.isNotEmpty && unpriced > 0) ...[
              const SizedBox(height: 10),
              _note(
                context,
                '$unpriced of ${matches.length} entries are excluded: the '
                'source has no quantity or unit to price them by.',
                Theme.of(context).colorScheme.onSurfaceVariant,
                Icons.info_outline,
              ),
            ],
            if (query.showEntries) ...[
              const Divider(height: 32),
              Text('Entries', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...priced
                  .take(200)
                  .map(
                    (p) => _EntryTile(
                      entry: p.$1,
                      perUnit: p.$2,
                      unitName: unitName,
                    ),
                  ),
              if (priced.length > 200)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Showing the first 200 of ${priced.length}. Narrow the year '
                    'range or place to see more precisely.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// True when the priced entries span so wide a range that a mean would
  /// mislead.
  ///
  /// This used to be a proxy for mixed-up units. It no longer needs to be —
  /// entries measured in the wrong kind of unit are excluded outright now — so
  /// what remains is real: a broad category like Food holds both barley at a
  /// fraction of a penny per kilogram and spices at thousands.
  bool _isWidelySpread(List<double> sorted) {
    if (sorted.length < 5) return false;
    final median = sorted[sorted.length ~/ 2];
    if (median <= 0) return false;
    return sorted.last / median > 100;
  }

  String _spreadFactor(List<double> sorted) {
    final median = sorted[sorted.length ~/ 2];
    final factor = sorted.last / median;
    return factor >= 1000
        ? '${(factor / 1000).round()},000'
        : factor.round().toString();
  }

  Widget _note(BuildContext context, String text, Color color, IconData icon) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      );

  double _stat(List<double> sorted, AverageKind kind) {
    switch (kind) {
      case AverageKind.mean:
        return sorted.reduce((a, b) => a + b) / sorted.length;
      case AverageKind.median:
        final mid = sorted.length ~/ 2;
        return sorted.length.isOdd
            ? sorted[mid]
            : (sorted[mid - 1] + sorted[mid]) / 2;
      case AverageKind.mode:
        final counts = <double, int>{};
        for (final v in sorted) {
          final bucket = (v * 100).round() / 100;
          counts[bucket] = (counts[bucket] ?? 0) + 1;
        }
        return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      case AverageKind.all:
        return sorted.isEmpty ? 0 : sorted.first;
    }
  }
}

/// Pounds, rounded no finer than the conversion can support.
///
/// "about" precedes it everywhere it is shown: the factor behind it is quoted
/// to two decimals and rests on a scholarly judgement, so a figure to the
/// penny would be claiming a precision nobody has.
String _poundsLabel(double value) {
  if (value >= 1000) return '\u00a3${value.round()}';
  if (value >= 1) return '\u00a3${value.toStringAsFixed(2)}';
  return '\u00a3${value.toStringAsFixed(3)}';
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unitName,
    required this.sampleSize,
    this.modern,
    this.modernYear,
  });

  final String label;
  final double value;
  final String unitName;
  final int sampleSize;

  /// The same statistic over the same entries, each converted by its own
  /// year's factor before averaging. Null where the database has no factors,
  /// or where none of the sampled entries could be converted.
  final double? modern;
  final int? modernYear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.paid_outlined, color: scheme.onPrimaryContainer),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  '${formatPence(value)} pence per $unitName',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                if (modern != null && modernYear != null)
                  Text(
                    'about ${_poundsLabel(modern!)} in $modernYear money',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                      fontSize: 15,
                    ),
                  ),
                Text(
                  'from $sampleSize priced '
                  '${sampleSize == 1 ? 'entry' : 'entries'}',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.perUnit,
    required this.unitName,
  });

  final PriceEntry entry;
  final double perUnit;
  final String unitName;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('${entry.year} · ${entry.placeLabel} · ${entry.priceLabel}'),
      subtitle: Text(
        [
          '${formatPence(perUnit)} pence per $unitName',
          if (entry.statusInfo != null) entry.statusInfo!,
        ].join('  ·  '),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => openEntryEditor(context, entry),
    );
  }
}

/// The year range, swept rather than typed.
class _YearSlider extends StatelessWidget {
  const _YearSlider({
    required this.min,
    required this.max,
    required this.values,
    required this.onChanged,
  });

  final int min;
  final int max;
  final RangeValues values;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: Spacing.sm, right: Spacing.sm),
      child: Row(
        children: [
          Text('$min',
              style: theme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [tabularFigures])),
          Expanded(
            child: RangeSlider(
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              values: values,
              labels: RangeLabels(
                '${values.start.round()}',
                '${values.end.round()}',
              ),
              onChanged: (r) => onChanged(RangeValues(
                r.start.roundToDouble(),
                r.end.roundToDouble(),
              )),
            ),
          ),
          Text('$max',
              style: theme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [tabularFigures])),
        ],
      ),
    );
  }
}

/// The question this answer is to, with its last level carrying the weight.
class _QueryLabel extends StatelessWidget {
  const _QueryLabel({required this.query});
  final _Query query;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.titleMedium;
    final parts = [query.category?.name, query.subcategory?.name,
            query.specific?.name]
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toList();
    if (parts.isEmpty) return Text('—', style: base);

    return Text.rich(
      TextSpan(
        children: [
          if (parts.length > 1)
            TextSpan(
              text: '${parts.sublist(0, parts.length - 1).join(' / ')} / ',
              style: base?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          TextSpan(
            text: parts.last,
            style: base?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The shape of the sample behind the headline figure.
///
/// Only shown at the fullest detail level, because it answers a question the
/// other two are not asking: an average over a spread this wide is a summary
/// of very different records, and the only honest way to say so is to show the
/// ends of it.
class _Spread extends StatelessWidget {
  const _Spread({required this.values, required this.unitName});

  /// Ascending, and never empty when this is built.
  final List<double> values;
  final String unitName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mid = values.length ~/ 2;
    final median = values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
    final mean = values.reduce((a, b) => a + b) / values.length;

    final figures = <(String, double)>[
      ('Lowest', values.first),
      ('Median', median),
      ('Mean', mean),
      ('Highest', values.last),
    ];

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The ${values.length} priced entries, in pence per $unitName',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.xl,
            runSpacing: Spacing.sm,
            children: [
              for (final (label, value) in figures)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      formatPence(value),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: const [tabularFigures],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
