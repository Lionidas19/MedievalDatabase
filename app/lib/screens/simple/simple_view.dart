import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../state/app_controller.dart';
import '../advanced/advanced_view.dart' show openEntryEditor;

/// How much of the question the reader wants to fill in.
///
/// The researcher sketched two versions of this screen and named them
/// "CACTUS VERSION" and "NOT AS CACTUS". Cactus asks the fewest questions it
/// can: a country, a span of years, one item. The other adds region and
/// locality, the full category chain, and a time period. Same question, same
/// answer — only the number of decisions differs.
enum LookupDetail { simple, detailed }

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

extension _LookupDetailLabel on LookupDetail {
  String get label => this == LookupDetail.simple ? 'Simple' : 'Detailed';
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
    if (county != null && e.county != county) return false;
    if (locality != null && e.locality != locality) return false;
    if (timePeriod != null && e.timePeriodName != timePeriod) return false;
    return true;
  }

  String get label => [category?.name, subcategory?.name, specific?.name]
      .where((s) => s != null)
      .join(' / ');

  String get whereLabel {
    if (locality != null) return ' in $locality';
    if (county != null) return ' in $county';
    return '';
  }
}

class SimpleView extends StatefulWidget {
  const SimpleView({super.key});

  @override
  State<SimpleView> createState() => _SimpleViewState();
}

class _SimpleViewState extends State<SimpleView> {
  LookupDetail _detail = LookupDetail.simple;

  CategoryOption? _category;
  SubcategoryOption? _subcategory;
  SpecificOption? _specific;
  RangeValues? _yearRange;
  LookupItem? _county;
  String? _locality;
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

  bool get _isSimple => _detail == LookupDetail.simple;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final repo = app.repository;
    final (minYear, maxYear) = repo.yearRange;
    _yearRange ??= RangeValues(minYear.toDouble(), maxYear.toDouble());

    final outputUnits = repo.outputUnitChoices;
    _outputUnit ??= _defaultOutputUnit(outputUnits);

    final categories = repo.categories;
    final subcategories = _category == null
        ? <SubcategoryOption>[]
        : repo.subcategoriesOf(_category!.id);
    final specifics = _subcategory == null
        ? <SpecificOption>[]
        : repo.specificsOf(_subcategory!.id);

    final countries = repo.countries;
    final counties = repo.counties;
    final localities = repo.localities(countyId: _county?.id);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.eco,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Text('Quick lookup',
                              style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSimple
                            ? 'Ask in plain English. Switch to Detailed for '
                                'region, locality and time of year.'
                            : 'Every filter the records support.',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      // Its own row rather than trailing the title: sharing a
                      // Row with a Spacer left the chips a hair too little
                      // width and clipped their last letter.
                      _ChoiceRow<LookupDetail>(
                        values: LookupDetail.values,
                        selected: _detail,
                        labelOf: (d) => d.label,
                        onSelected: (d) => setState(() => _detail = d),
                      ),
                      const SizedBox(height: 20),

                      // --- where ---
                      _sentenceRow([
                        const Text('In'),
                        if (countries.length == 1)
                          _fixedValue(context, countries.first.label)
                        else
                          _dropdown<String?>(
                            width: 150,
                            value: null,
                            hint: 'any country',
                            entries: [
                              const DropdownMenuEntry(
                                  value: null, label: 'Any country'),
                              ...countries.map((c) => DropdownMenuEntry(
                                  value: c.label, label: c.label)),
                            ],
                            onSelected: (_) {},
                          ),
                        if (!_isSimple) ...[
                          _dropdown<LookupItem?>(
                            width: 190,
                            value: _county,
                            hint: 'any region',
                            entries: [
                              const DropdownMenuEntry(
                                  value: null, label: 'Any region'),
                              ...counties.map((c) =>
                                  DropdownMenuEntry(value: c, label: c.label)),
                            ],
                            onSelected: (v) => setState(() {
                              _county = v;
                              _locality = null;
                            }),
                          ),
                          _dropdown<String?>(
                            width: 190,
                            value: _locality,
                            hint: 'any locality',
                            entries: [
                              const DropdownMenuEntry(
                                  value: null, label: 'Any locality'),
                              ...localities.map((l) => DropdownMenuEntry(
                                  value: l.label, label: l.label)),
                            ],
                            onSelected: (v) => setState(() => _locality = v),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 12),

                      // --- when ---
                      _sentenceRow([
                        const Text('Between the years'),
                        _yearField(isStart: true, min: minYear, max: maxYear),
                        const Text('and'),
                        _yearField(isStart: false, min: minYear, max: maxYear),
                        if (!_isSimple) ...[
                          const Text('at'),
                          _dropdown<String?>(
                            width: 210,
                            value: _timePeriod,
                            hint: 'any time of year',
                            entries: [
                              const DropdownMenuEntry(
                                  value: null, label: 'Any time of year'),
                              ...repo.timePeriods.map((t) => DropdownMenuEntry(
                                  value: t.label, label: t.label)),
                            ],
                            onSelected: (v) => setState(() => _timePeriod = v),
                          ),
                        ],
                      ]),
                      if (!_isSimple)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 2),
                          child: Text(
                            'Time of year mixes months, seasons and feast days, '
                            'exactly as the records do.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ),
                      const SizedBox(height: 12),

                      // --- what ---
                      _sentenceRow([
                        const Text('Item:'),
                        _dropdown<CategoryOption?>(
                          width: 180,
                          value: _category,
                          hint: 'category',
                          entries: categories
                              .map((c) =>
                                  DropdownMenuEntry(value: c, label: c.name))
                              .toList(),
                          onSelected: (v) => setState(() {
                            _category = v;
                            _subcategory = null;
                            _specific = null;
                          }),
                        ),
                        _dropdown<SubcategoryOption?>(
                          width: 180,
                          value: _subcategory,
                          hint: 'subcategory',
                          enabled: _category != null,
                          entries: subcategories
                              .map((s) =>
                                  DropdownMenuEntry(value: s, label: s.name))
                              .toList(),
                          onSelected: (v) => setState(() {
                            _subcategory = v;
                            _specific = null;
                          }),
                        ),
                        if (!_isSimple)
                          _dropdown<SpecificOption?>(
                            width: 180,
                            value: _specific,
                            hint: 'specific',
                            enabled: _subcategory != null,
                            entries: specifics
                                .map((s) =>
                                    DropdownMenuEntry(value: s, label: s.name))
                                .toList(),
                            onSelected: (v) => setState(() => _specific = v),
                          ),
                      ]),
                      const SizedBox(height: 12),

                      // --- in what unit ---
                      // The control this whole rewrite exists to make
                      // possible: the answer is computed per entry in
                      // whichever unit is picked, not read from a fixed
                      // column.
                      _sentenceRow([
                        const Text('was valued at how many pence per'),
                        _dropdown<MetricItem?>(
                          width: 230,
                          value: _outputUnit,
                          hint: 'unit',
                          entries: (_isSimple
                                  ? _commonUnits(outputUnits)
                                  : outputUnits)
                              .map((u) => DropdownMenuEntry(
                                    value: u,
                                    label: u.dimension == null
                                        ? u.name
                                        : '${u.name}  (${u.dimension})',
                                  ))
                              .toList(),
                          onSelected: (v) => setState(() => _outputUnit = v),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      Text('Show', style: Theme.of(context).textTheme.labelLarge),
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
                        title: const Text('Show original data entries'),
                        value: _showEntries,
                        onChanged: (v) => setState(() => _showEntries = v),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _category == null
                              ? null
                              : () => setState(() => _generated = true),
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Generate results'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_generated && _category != null) ...[
                const SizedBox(height: 20),
                _ResultCard(
                  query: _Query(
                    category: _category,
                    subcategory: _subcategory,
                    specific: _isSimple ? null : _specific,
                    years: _yearRange!,
                    county: _isSimple ? null : _county?.label,
                    locality: _isSimple ? null : _locality,
                    timePeriod: _isSimple ? null : _timePeriod,
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

  /// Kilograms is the unit a lay reader expects; fall back to whatever the
  /// source offers if it is absent.
  MetricItem? _defaultOutputUnit(List<MetricItem> units) {
    if (units.isEmpty) return null;
    for (final name in ['Kilograms', 'Grams', 'Litres']) {
      for (final u in units) {
        if (u.name == name) return u;
      }
    }
    return units.first;
  }

  /// A short list for the simple view. 97 output units is a research tool, not
  /// a question to put to somebody who wants the price of wheat.
  List<MetricItem> _commonUnits(List<MetricItem> units) {
    const wanted = [
      'Kilograms', 'Grams', 'Litres', 'US Pounds', 'Tower Pound', 'Troy Pound',
    ];
    final short = [
      for (final name in wanted)
        ...units.where((u) => u.name == name),
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

  Widget _yearField(
      {required bool isStart, required int min, required int max}) {
    final value = isStart ? _yearRange!.start : _yearRange!.end;
    return SizedBox(
      width: 100,
      child: TextFormField(
        key: ValueKey('$isStart-${_yearRange!.start}-${_yearRange!.end}'),
        initialValue: value.round().toString(),
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(isDense: true),
        onChanged: (text) {
          final v = double.tryParse(text);
          if (v == null) return;
          setState(() {
            _yearRange = isStart
                ? RangeValues(
                    v.clamp(min.toDouble(), max.toDouble()), _yearRange!.end)
                : RangeValues(
                    _yearRange!.start, v.clamp(min.toDouble(), max.toDouble()));
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
  }) {
    return SizedBox(
      width: width,
      child: DropdownMenu<T>(
        width: width,
        enabled: enabled,
        hintText: hint,
        initialSelection: value,
        dropdownMenuEntries: entries,
        onSelected: (v) {
          if (v != null || entries.any((e) => e.value == null)) {
            onSelected(v as T);
          }
        },
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.query});
  final _Query query;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final matches = app.entries.where(query.matches).toList();

    // Every value is computed in the same reader-chosen unit, so averaging
    // them is meaningful. Reading a stored per-unit column instead would mix
    // quarters, kilograms and acres into one meaningless number.
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
      final v = e.calculate(outputY: query.outputUnit).pencePerOutputY;
      if (v == null || !v.isFinite) {
        unpriced++;
      } else {
        priced.add((e, v));
      }
    }
    final values = priced.map((p) => p.$2).toList()..sort();
    final unitName = query.outputUnit?.name ?? 'unit';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(query.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${matches.length} matching entr${matches.length == 1 ? 'y' : 'ies'} '
              'between ${query.years.start.round()} and '
              '${query.years.end.round()}${query.whereLabel}'
              '${query.timePeriod != null ? ', ${query.timePeriod}' : ''}',
              style:
                  TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
              )
            else
              Text('${values.length} priced entries found — see the list below.'),
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
              ...priced.take(200).map((p) =>
                  _EntryTile(entry: p.$1, perUnit: p.$2, unitName: unitName)),
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
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.unitName,
    required this.sampleSize,
  });

  final String label;
  final double value;
  final String unitName;
  final int sampleSize;

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
                Text(label,
                    style: TextStyle(
                        color:
                            scheme.onPrimaryContainer.withValues(alpha: 0.8))),
                Text(
                  '${formatPence(value)} pence per $unitName',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
                Text(
                  'from $sampleSize priced '
                  '${sampleSize == 1 ? 'entry' : 'entries'}',
                  style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                      fontSize: 12),
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
          '${formatPence(perUnit)}d per $unitName',
          if (entry.statusInfo != null) entry.statusInfo!,
        ].join('  ·  '),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => openEntryEditor(context, entry),
    );
  }
}
