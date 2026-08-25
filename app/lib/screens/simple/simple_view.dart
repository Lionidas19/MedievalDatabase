import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../state/app_controller.dart';
import '../advanced/advanced_view.dart' show openEntryEditor;

class SimpleView extends StatefulWidget {
  const SimpleView({super.key});

  @override
  State<SimpleView> createState() => _SimpleViewState();
}

class _SimpleViewState extends State<SimpleView> {
  CategoryOption? _category;
  SubcategoryOption? _subcategory;
  SpecificOption? _specific;
  RangeValues? _yearRange;
  String? _county;
  MetricItem? _outputUnit;

  // Median by default, not mean. The source's measures mix dimensions —
  // 'Heads/Units' is a count, 'Tun, Wine' is litres, 'Little Pound, Spices' is
  // grams — so a broad selection can contain values many thousands of times
  // apart and a mean says almost nothing. Food across the whole range has a
  // median of 0.17 pence/kg and a mean of 366.
  AverageKind _kind = AverageKind.median;
  bool _showEntries = false;
  bool _generated = false;

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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
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
                        'Pick an item, a date range, and (optionally) a place — '
                        'in plain English, no filters to configure.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      _sentenceRow([
                        const Text('In'),
                        _dropdown<String?>(
                          width: 190,
                          value: _county,
                          hint: 'any county',
                          entries: [
                            const DropdownMenuEntry(
                                value: null, label: 'Any county'),
                            ...repo.counties.map((c) =>
                                DropdownMenuEntry(value: c.label, label: c.label)),
                          ],
                          onSelected: (v) => setState(() => _county = v),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _sentenceRow([
                        const Text('Between the years'),
                        _yearField(isStart: true, min: minYear, max: maxYear),
                        const Text('and'),
                        _yearField(isStart: false, min: minYear, max: maxYear),
                      ]),
                      const SizedBox(height: 12),
                      _sentenceRow([
                        const Text('Item:'),
                        _dropdown<CategoryOption?>(
                          width: 170,
                          value: _category,
                          hint: 'category',
                          entries: categories
                              .map((c) => DropdownMenuEntry(value: c, label: c.name))
                              .toList(),
                          onSelected: (v) => setState(() {
                            _category = v;
                            _subcategory = null;
                            _specific = null;
                          }),
                        ),
                        _dropdown<SubcategoryOption?>(
                          width: 170,
                          value: _subcategory,
                          hint: 'subcategory',
                          enabled: _category != null,
                          entries: subcategories
                              .map((s) => DropdownMenuEntry(value: s, label: s.name))
                              .toList(),
                          onSelected: (v) => setState(() {
                            _subcategory = v;
                            _specific = null;
                          }),
                        ),
                        _dropdown<SpecificOption?>(
                          width: 170,
                          value: _specific,
                          hint: 'specific',
                          enabled: _subcategory != null,
                          entries: specifics
                              .map((s) => DropdownMenuEntry(value: s, label: s.name))
                              .toList(),
                          onSelected: (v) => setState(() => _specific = v),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // The control the whole rewrite exists to make possible:
                      // the answer is computed per entry in whichever unit is
                      // picked here, rather than read from a fixed column.
                      _sentenceRow([
                        const Text('was valued at how many pence per'),
                        _dropdown<MetricItem?>(
                          width: 220,
                          value: _outputUnit,
                          hint: 'unit',
                          entries: outputUnits
                              .map((u) => DropdownMenuEntry(value: u, label: u.name))
                              .toList(),
                          onSelected: (v) => setState(() => _outputUnit = v),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Text('Show',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<AverageKind>(
                        // The selected-item checkmark steals enough width to
                        // wrap and clip the labels.
                        showSelectedIcon: false,
                        segments: AverageKind.values
                            .map((k) =>
                                ButtonSegment(value: k, label: Text(k.shortLabel)))
                            .toList(),
                        selected: {_kind},
                        onSelectionChanged: (s) => setState(() => _kind = s.first),
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
                  category: _category!,
                  subcategory: _subcategory,
                  specific: _specific,
                  yearRange: _yearRange!,
                  county: _county,
                  outputUnit: _outputUnit,
                  kind: _kind,
                  showEntries: _showEntries,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Kilograms is the unit a lay reader will expect; fall back to whatever the
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

  Widget _sentenceRow(List<Widget> children) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: children,
      );

  Widget _yearField({required bool isStart, required int min, required int max}) {
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
          if (v != null || entries.any((e) => e.value == null)) onSelected(v as T);
        },
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.category,
    required this.subcategory,
    required this.specific,
    required this.yearRange,
    required this.county,
    required this.outputUnit,
    required this.kind,
    required this.showEntries,
  });

  final CategoryOption category;
  final SubcategoryOption? subcategory;
  final SpecificOption? specific;
  final RangeValues yearRange;
  final String? county;
  final MetricItem? outputUnit;
  final AverageKind kind;
  final bool showEntries;

  List<PriceEntry> _matches(AppController app) {
    return app.entries.where((e) {
      if (e.category != category.name) return false;
      if (subcategory != null && e.subcategory != subcategory!.name) return false;
      if (specific != null && e.specific != specific!.name) return false;
      final y = e.year;
      if (y == null || y < yearRange.start || y > yearRange.end) return false;
      if (county != null && e.county != county) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final matches = _matches(app);
    final label = [category.name, subcategory?.name, specific?.name]
        .where((s) => s != null)
        .join(' / ');

    // Every value is computed in the same reader-chosen unit, so averaging
    // them is meaningful. Reading a stored per-unit column instead would mix
    // quarters, kilograms and acres into one meaningless number.
    final priced = <(PriceEntry, double)>[];
    var unpriced = 0;
    for (final e in matches) {
      final v = e.calculate(outputY: outputUnit).pencePerOutputY;
      if (v == null || !v.isFinite) {
        unpriced++;
      } else {
        priced.add((e, v));
      }
    }
    final values = priced.map((p) => p.$2).toList()..sort();
    final unitName = outputUnit?.name ?? 'unit';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${matches.length} matching entr${matches.length == 1 ? 'y' : 'ies'} '
              'between ${yearRange.start.round()} and ${yearRange.end.round()}'
              '${county != null ? ' in $county' : ''}',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (values.isEmpty)
              Text(
                matches.isEmpty
                    ? 'No entries match this lookup.'
                    : 'None of the ${matches.length} matching entries can be '
                        'priced per $unitName — their quantities or units are '
                        'missing from the source.',
              )
            else if (kind != AverageKind.all)
              _StatTile(
                label: kind.label,
                value: _stat(values, kind),
                unitName: unitName,
                sampleSize: values.length,
              )
            else
              Text('${values.length} priced entries found — see the list below.'),
            if (values.isNotEmpty && _looksDimensionallyMixed(values)) ...[
              const SizedBox(height: 10),
              _note(
                context,
                'These entries are not all measured in the same kind of unit — '
                'the source counts some goods by head or by the dozen and '
                'others by weight or volume, and only weights convert honestly '
                'to $unitName. Narrow the item to compare like with like; the '
                'median is far more trustworthy than the mean here.',
                Theme.of(context).colorScheme.error,
                Icons.warning_amber_outlined,
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
            if (showEntries) ...[
              const Divider(height: 32),
              Text('Entries', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...priced.take(200).map(
                  (p) => _EntryTile(entry: p.$1, perUnit: p.$2, unitName: unitName)),
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

  /// True when the spread is so wide that the selection almost certainly mixes
  /// counts, weights and volumes together.
  ///
  /// The source has no dimension label on a measure, so this cannot be checked
  /// directly — but genuine price variation within one kind of good stays
  /// within an order of magnitude or two, whereas pricing 100 head of cattle
  /// "per kilogram" lands three orders out. A hundredfold gap between the
  /// median and the largest value is a reliable tell.
  bool _looksDimensionallyMixed(List<double> sorted) {
    if (sorted.length < 5) return false;
    final median = sorted[sorted.length ~/ 2];
    if (median <= 0) return false;
    return sorted.last / median > 100;
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
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
                Text(
                  '${formatPence(value)} pence per $unitName',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
                Text(
                  'from $sampleSize priced ${sampleSize == 1 ? 'entry' : 'entries'}',
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
