import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/database_repository.dart';
import '../../state/app_controller.dart';
import '../advanced/edit_entry_dialog.dart';

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
  AverageKind _kind = AverageKind.mean;
  bool _showEntries = false;
  bool _generated = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final repo = app.repository;
    final (minYear, maxYear) = repo.yearRange;
    _yearRange ??= RangeValues(minYear.toDouble(), maxYear.toDouble());

    final categories = repo.categories;
    final subcategories = _category == null ? <SubcategoryOption>[] : repo.subcategoriesOf(_category!.id);
    final specifics = _subcategory == null ? <SpecificOption>[] : repo.specificsOf(_subcategory!.id);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
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
                          Icon(Icons.eco, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          Text('Quick lookup', style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pick an item, a date range, and (optionally) a place — '
                        'in plain English, no filters to configure.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      _sentenceRow(context, [
                        const Text('In'),
                        _dropdown<String?>(
                          width: 180,
                          value: _county,
                          hint: 'any county',
                          entries: [
                            const DropdownMenuEntry(value: null, label: 'Any county'),
                            ...repo.counties.map((c) => DropdownMenuEntry(value: c.label, label: c.label)),
                          ],
                          onSelected: (v) => setState(() => _county = v),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      _sentenceRow(context, [
                        const Text('Between the years'),
                        _yearField(context, isStart: true, min: minYear, max: maxYear),
                        const Text('and'),
                        _yearField(context, isStart: false, min: minYear, max: maxYear),
                      ]),
                      const SizedBox(height: 12),
                      _sentenceRow(context, [
                        const Text('Item:'),
                        _dropdown<CategoryOption?>(
                          width: 180,
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
                          width: 180,
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
                          width: 180,
                          value: _specific,
                          hint: 'specific',
                          enabled: _subcategory != null,
                          entries: specifics
                              .map((s) => DropdownMenuEntry(value: s, label: s.name))
                              .toList(),
                          onSelected: (v) => setState(() => _specific = v),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Text('Show', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      SegmentedButton<AverageKind>(
                        segments: AverageKind.values
                            .map((k) => ButtonSegment(value: k, label: Text(k.label)))
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
                          onPressed: _category == null ? null : () => setState(() => _generated = true),
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
                  repository: repo,
                  category: _category!,
                  subcategory: _subcategory,
                  specific: _specific,
                  yearRange: _yearRange!,
                  county: _county,
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

  Widget _sentenceRow(BuildContext context, List<Widget> children) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: children,
    );
  }

  Widget _yearField(BuildContext context, {required bool isStart, required int min, required int max}) {
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
                ? RangeValues(v.clamp(min.toDouble(), max.toDouble()), _yearRange!.end)
                : RangeValues(_yearRange!.start, v.clamp(min.toDouble(), max.toDouble()));
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
    required this.repository,
    required this.category,
    required this.subcategory,
    required this.specific,
    required this.yearRange,
    required this.county,
    required this.kind,
    required this.showEntries,
  });

  final DatabaseRepository repository;
  final CategoryOption category;
  final SubcategoryOption? subcategory;
  final SpecificOption? specific;
  final RangeValues yearRange;
  final String? county;
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

    final values = matches.map((e) => e.pencePerOutputY).whereType<double>().toList()..sort();

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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (values.isEmpty)
              const Text('No priced entries match this lookup yet.')
            else if (kind != AverageKind.all)
              _StatTile(label: kind.label, value: _stat(values, kind), unitHint: matches.first.outputYName)
            else
              Text('${values.length} priced entries found — see the list below.'),
            if (showEntries) ...[
              const Divider(height: 32),
              Text('Entries', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...matches.take(200).map((e) => _EntryTile(entry: e)),
              if (matches.length > 200)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Showing the first 200 of ${matches.length}. Narrow the year range or place to see more precisely.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  double _stat(List<double> sorted, AverageKind kind) {
    switch (kind) {
      case AverageKind.mean:
        return sorted.reduce((a, b) => a + b) / sorted.length;
      case AverageKind.median:
        final mid = sorted.length ~/ 2;
        return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
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
  const _StatTile({required this.label, required this.value, this.unitHint});
  final String label;
  final double value;
  final String? unitHint;

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
              Text(
                '${value.toStringAsFixed(3)} pence per ${unitHint ?? 'unit'}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final PriceEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('${entry.year} · ${entry.placeLabel} · ${entry.priceLabel}'),
      subtitle: entry.statusInfo == null ? null : Text(entry.statusInfo!),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () async {
        final app = context.read<AppController>();
        final updated = await showEditEntryDialog(context, entry: entry, repository: app.repository);
        if (updated != null) app.applyEdit(updated);
      },
    );
  }
}
