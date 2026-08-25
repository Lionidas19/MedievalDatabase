import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/pricing.dart';
import '../../state/app_controller.dart';
import '../../theme.dart';
import 'edit_entry_dialog.dart';

enum _SortField { year, place, category, quantity, price, perUnit, page }

/// Roughly a quarter of the database has no year at all. The year slider
/// alone cannot express "show me those", and worse, it silently swallowed
/// them — so undated entries are their own filter rather than a side effect.
enum _DateFilter { any, dated, undated }

extension _DateFilterLabel on _DateFilter {
  String get label => switch (this) {
        _DateFilter.any => 'Dated and undated',
        _DateFilter.dated => 'Dated only',
        _DateFilter.undated => 'Undated only',
      };
}

/// An entry paired with its price in the currently chosen output unit, so the
/// table can sort and display without recomputing per cell.
typedef _Priced = (PriceEntry entry, double? perUnit);

class AdvancedView extends StatefulWidget {
  const AdvancedView({super.key});

  @override
  State<AdvancedView> createState() => _AdvancedViewState();
}

class _AdvancedViewState extends State<AdvancedView> {
  final _searchController = TextEditingController();
  String _search = '';
  Timer? _debounce;

  RangeValues? _yearRange;
  String? _countyFilter;
  String? _categoryFilter;
  MetricItem? _outputUnit;
  // Nothing hidden by default. Every real entry currently carries a year —
  // the 2,579 that appeared undated were the Data sheet's blank template
  // rows, which the import now skips. The filter stays because undated
  // entries are a legitimate thing for the source to contain, and silently
  // dropping them is how they went unnoticed in the first place.
  _DateFilter _dateFilter = _DateFilter.any;

  _SortField _sortField = _SortField.year;
  bool _ascending = true;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      setState(() => _search = value);
    });
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) {
        _ascending = !_ascending;
      } else {
        _sortField = field;
        _ascending = true;
      }
    });
  }

  int _compare(_Priced a, _Priced b) {
    int cmp;
    switch (_sortField) {
      case _SortField.year:
        // Undated entries sort last in both directions. Treating a missing
        // year as 0 would park them permanently at the top of an ascending
        // sort, which is where they are least useful.
        final ay = a.$1.year, by = b.$1.year;
        if (ay == null && by == null) return 0;
        if (ay == null) return 1;
        if (by == null) return -1;
        cmp = ay.compareTo(by);
      case _SortField.place:
        cmp = a.$1.placeLabel.toLowerCase().compareTo(b.$1.placeLabel.toLowerCase());
      case _SortField.category:
        cmp = a.$1.categoryLabel
            .toLowerCase()
            .compareTo(b.$1.categoryLabel.toLowerCase());
      case _SortField.quantity:
        cmp = (a.$1.unit1 ?? 0).compareTo(b.$1.unit1 ?? 0);
      case _SortField.price:
        final ap = (a.$1.pounds ?? 0) * 240 +
            (a.$1.shillings ?? 0) * 12 +
            (a.$1.pence ?? 0);
        final bp = (b.$1.pounds ?? 0) * 240 +
            (b.$1.shillings ?? 0) * 12 +
            (b.$1.pence ?? 0);
        cmp = ap.compareTo(bp);
      case _SortField.perUnit:
        // Entries with no computable price sort last in both directions —
        // they are absent data, not a value of zero.
        final av = a.$2, bv = b.$2;
        if (av == null && bv == null) return 0;
        if (av == null) return 1;
        if (bv == null) return -1;
        cmp = av.compareTo(bv);
      case _SortField.page:
        cmp = (a.$1.page ?? 0).compareTo(b.$1.page ?? 0);
    }
    return _ascending ? cmp : -cmp;
  }

  /// True when [entry] passes the date filter.
  ///
  /// Under [_DateFilter.any] an undated entry is kept regardless of the year
  /// slider — the slider constrains the entries that have a year, and cannot
  /// say anything about the ones that do not.
  bool _passesDate(PriceEntry entry, RangeValues? range) {
    final year = entry.year;
    switch (_dateFilter) {
      case _DateFilter.undated:
        return year == null;
      case _DateFilter.dated:
        if (year == null) return false;
        return range == null || (year >= range.start && year <= range.end);
      case _DateFilter.any:
        if (year == null) return true;
        return range == null || (year >= range.start && year <= range.end);
    }
  }

  List<_Priced> _filtered(AppController app) {
    final q = _search.trim().toLowerCase();
    final yr = _yearRange;

    final list = app.entries.where((e) {
      if (q.isNotEmpty) {
        final hay = [
          e.locality, e.county, e.category, e.subcategory, e.specific,
          e.statusInfo, e.information, e.sourceCitation, e.food,
        ].where((s) => s != null).join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (!_passesDate(e, yr)) return false;
      if (_countyFilter != null && e.county != _countyFilter) return false;
      if (_categoryFilter != null && e.category != _categoryFilter) return false;
      return true;
    }).toList();

    final priced = [
      for (final e in list)
        (e, e.calculate(outputY: _outputUnit).pencePerOutputY),
    ];
    priced.sort(_compare);
    return priced;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final repo = app.repository;
    final (minYear, maxYear) = repo.yearRange;
    _yearRange ??= RangeValues(minYear.toDouble(), maxYear.toDouble());

    final outputUnits = repo.outputUnitChoices;
    _outputUnit ??= _defaultOutputUnit(outputUnits);

    final filtered = _filtered(app);
    final compact = Breakpoints.isCompact(MediaQuery.sizeOf(context).width);
    final unitName = _outputUnit?.name ?? 'unit';

    return Column(
      children: [
        _FilterBar(
          searchController: _searchController,
          onSearchChanged: _onSearchChanged,
          minYear: minYear,
          maxYear: maxYear,
          yearRange: _yearRange!,
          onYearRangeChanged: (r) => setState(() => _yearRange = r),
          counties: repo.counties.map((c) => c.label).toList(),
          countyFilter: _countyFilter,
          onCountyChanged: (v) => setState(() => _countyFilter = v),
          categories: repo.categories.map((c) => c.name).toList(),
          categoryFilter: _categoryFilter,
          onCategoryChanged: (v) => setState(() => _categoryFilter = v),
          outputUnits: outputUnits,
          outputUnit: _outputUnit,
          onOutputUnitChanged: (v) => setState(() => _outputUnit = v),
          dateFilter: _dateFilter,
          onDateFilterChanged: (v) => setState(() => _dateFilter = v),
          undatedTotal: app.entries.where((e) => e.year == null).length,
          resultCount: filtered.length,
          totalCount: app.entries.length,
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No entries match these filters.'))
              : compact
                  ? _CompactList(entries: filtered, unitName: unitName)
                  : _TableView(
                      entries: filtered,
                      unitName: unitName,
                      sortField: _sortField,
                      ascending: _ascending,
                      onSort: _toggleSort,
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.searchController,
    required this.onSearchChanged,
    required this.minYear,
    required this.maxYear,
    required this.yearRange,
    required this.onYearRangeChanged,
    required this.counties,
    required this.countyFilter,
    required this.onCountyChanged,
    required this.categories,
    required this.categoryFilter,
    required this.onCategoryChanged,
    required this.outputUnits,
    required this.outputUnit,
    required this.onOutputUnitChanged,
    required this.dateFilter,
    required this.onDateFilterChanged,
    required this.undatedTotal,
    required this.resultCount,
    required this.totalCount,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final int minYear;
  final int maxYear;
  final RangeValues yearRange;
  final ValueChanged<RangeValues> onYearRangeChanged;
  final List<String> counties;
  final String? countyFilter;
  final ValueChanged<String?> onCountyChanged;
  final List<String> categories;
  final String? categoryFilter;
  final ValueChanged<String?> onCategoryChanged;
  final List<MetricItem> outputUnits;
  final MetricItem? outputUnit;
  final ValueChanged<MetricItem?> onOutputUnitChanged;
  final _DateFilter dateFilter;
  final ValueChanged<_DateFilter> onDateFilterChanged;
  final int undatedTotal;
  final int resultCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search place, item, notes…',
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownMenu<String?>(
              width: 200,
              label: const Text('County'),
              initialSelection: countyFilter,
              onSelected: onCountyChanged,
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'Any county'),
                ...counties.map((c) => DropdownMenuEntry(value: c, label: c)),
              ],
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownMenu<String?>(
              width: 180,
              label: const Text('Category'),
              initialSelection: categoryFilter,
              onSelected: onCategoryChanged,
              dropdownMenuEntries: [
                const DropdownMenuEntry(value: null, label: 'Any category'),
                ...categories.map((c) => DropdownMenuEntry(value: c, label: c)),
              ],
            ),
          ),
          SizedBox(
            width: 210,
            child: DropdownMenu<MetricItem?>(
              width: 210,
              label: const Text('Price per'),
              initialSelection: outputUnit,
              onSelected: onOutputUnitChanged,
              dropdownMenuEntries: outputUnits
                  .map((u) => DropdownMenuEntry(value: u, label: u.name))
                  .toList(),
            ),
          ),
          SizedBox(
            width: 210,
            child: DropdownMenu<_DateFilter>(
              width: 210,
              label: const Text('Dates'),
              initialSelection: dateFilter,
              onSelected: (v) => onDateFilterChanged(v ?? _DateFilter.any),
              dropdownMenuEntries: _DateFilter.values
                  .map((d) => DropdownMenuEntry(
                        value: d,
                        label: d == _DateFilter.undated
                            ? '${d.label} ($undatedTotal)'
                            : d.label,
                      ))
                  .toList(),
            ),
          ),
          SizedBox(
            width: 240,
            child: Row(
              children: [
                Text('${yearRange.start.round()}',
                    style: Theme.of(context).textTheme.bodySmall),
                Expanded(
                  child: RangeSlider(
                    min: minYear.toDouble(),
                    max: maxYear.toDouble(),
                    values: yearRange,
                    // The slider can only speak about entries that have a
                    // year, so it is meaningless when showing only undated.
                    onChanged: dateFilter == _DateFilter.undated
                        ? null
                        : onYearRangeChanged,
                  ),
                ),
                Text('${yearRange.end.round()}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            '$resultCount of $totalCount entries',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (undatedTotal > 0)
            Text(
              switch (dateFilter) {
                _DateFilter.any => 'including undated',
                _DateFilter.dated => '$undatedTotal undated hidden',
                _DateFilter.undated => 'undated only',
              },
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _TableView extends StatelessWidget {
  const _TableView({
    required this.entries,
    required this.unitName,
    required this.sortField,
    required this.ascending,
    required this.onSort,
  });

  final List<_Priced> entries;
  final String unitName;
  final _SortField sortField;
  final bool ascending;
  final ValueChanged<_SortField> onSort;

  static const _flexes = [1, 2, 3, 2, 2, 2, 1];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          color: scheme.surfaceContainerHigh,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _headerCell('Year', _SortField.year, flex: _flexes[0]),
              _headerCell('Place', _SortField.place, flex: _flexes[1]),
              _headerCell('Category', _SortField.category, flex: _flexes[2]),
              _headerCell('Quantity', _SortField.quantity, flex: _flexes[3]),
              _headerCell('Price', _SortField.price, flex: _flexes[4]),
              _headerCell('d / $unitName', _SortField.perUnit, flex: _flexes[5]),
              _headerCell('Pg', _SortField.page, flex: _flexes[6]),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemExtent: 52,
            itemBuilder: (context, i) =>
                _EntryRow(priced: entries[i], flexes: _flexes),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(String label, _SortField field, {required int flex}) {
    final active = sortField == field;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => onSort(field),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                      fontWeight: active ? FontWeight.bold : FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active)
                Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.priced, required this.flexes});
  final _Priced priced;
  final List<int> flexes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = priced.$1;
    final perUnit = priced.$2;
    return InkWell(
      onTap: () => _edit(context, entry),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(flex: flexes[0], child: Text('${entry.year ?? ''}')),
            Expanded(
                flex: flexes[1],
                child: Text(entry.placeLabel, overflow: TextOverflow.ellipsis)),
            Expanded(
                flex: flexes[2],
                child:
                    Text(entry.categoryLabel, overflow: TextOverflow.ellipsis)),
            Expanded(
                flex: flexes[3],
                child:
                    Text(entry.quantityLabel, overflow: TextOverflow.ellipsis)),
            Expanded(flex: flexes[4], child: Text(entry.priceLabel)),
            Expanded(
              flex: flexes[5],
              child: Text(
                formatPence(perUnit),
                style: perUnit == null
                    ? TextStyle(color: scheme.onSurfaceVariant)
                    : null,
              ),
            ),
            Expanded(flex: flexes[6], child: Text('${entry.page ?? ''}')),
            SizedBox(
              width: 48,
              child: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _edit(context, entry),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, PriceEntry entry) async {
    final app = context.read<AppController>();
    final updated = await showEditEntryDialog(context,
        entry: entry, repository: app.repository);
    if (updated != null) app.applyEdit(updated);
  }
}

class _CompactList extends StatelessWidget {
  const _CompactList({required this.entries, required this.unitName});
  final List<_Priced> entries;
  final String unitName;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final (e, perUnit) = entries[i];
        return Card(
          child: ListTile(
            title: Text('${e.categoryLabel} — ${e.priceLabel}'),
            subtitle: Text(
              '${e.year ?? ''} · ${e.placeLabel}\n'
              '${formatPence(perUnit)}d per $unitName',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final app = context.read<AppController>();
              final updated = await showEditEntryDialog(context,
                  entry: e, repository: app.repository);
              if (updated != null) app.applyEdit(updated);
            },
          ),
        );
      },
    );
  }
}
