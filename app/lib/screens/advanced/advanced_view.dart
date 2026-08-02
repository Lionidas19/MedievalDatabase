import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../../theme.dart';
import 'edit_entry_dialog.dart';

enum _SortField { year, place, category, quantity, price, page }

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

  int _compare(PriceEntry a, PriceEntry b) {
    int cmp;
    switch (_sortField) {
      case _SortField.year:
        cmp = (a.year ?? 0).compareTo(b.year ?? 0);
      case _SortField.place:
        cmp = a.placeLabel.toLowerCase().compareTo(b.placeLabel.toLowerCase());
      case _SortField.category:
        cmp = a.categoryLabel.toLowerCase().compareTo(b.categoryLabel.toLowerCase());
      case _SortField.quantity:
        cmp = (a.unit1 ?? 0).compareTo(b.unit1 ?? 0);
      case _SortField.price:
        final ap = (a.pounds ?? 0) * 240 + (a.shillings ?? 0) * 12 + (a.pence ?? 0);
        final bp = (b.pounds ?? 0) * 240 + (b.shillings ?? 0) * 12 + (b.pence ?? 0);
        cmp = ap.compareTo(bp);
      case _SortField.page:
        cmp = (a.page ?? 0).compareTo(b.page ?? 0);
    }
    return _ascending ? cmp : -cmp;
  }

  List<PriceEntry> _filtered(AppController app) {
    var list = app.entries;
    final q = _search.trim().toLowerCase();
    final yr = _yearRange;

    if (q.isNotEmpty || yr != null || _countyFilter != null || _categoryFilter != null) {
      list = list.where((e) {
        if (q.isNotEmpty) {
          final hay = [
            e.locality, e.county, e.category, e.subcategory, e.specific,
            e.statusInfo, e.information, e.sourceCitation,
          ].where((s) => s != null).join(' ').toLowerCase();
          if (!hay.contains(q)) return false;
        }
        if (yr != null) {
          final y = e.year;
          if (y == null || y < yr.start || y > yr.end) return false;
        }
        if (_countyFilter != null && e.county != _countyFilter) return false;
        if (_categoryFilter != null && e.category != _categoryFilter) return false;
        return true;
      }).toList();
    } else {
      list = List.of(list);
    }

    list.sort(_compare);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final repo = app.repository;
    final (minYear, maxYear) = repo.yearRange;
    _yearRange ??= RangeValues(minYear.toDouble(), maxYear.toDouble());

    final filtered = _filtered(app);
    final compact = Breakpoints.isCompact(MediaQuery.sizeOf(context).width);

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
          resultCount: filtered.length,
          totalCount: app.entries.length,
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No entries match these filters.'))
              : compact
                  ? _CompactList(entries: filtered)
                  : _TableView(
                      entries: filtered,
                      sortField: _sortField,
                      ascending: _ascending,
                      onSort: _toggleSort,
                    ),
        ),
      ],
    );
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
            width: 260,
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
            width: 220,
            child: DropdownMenu<String?>(
              width: 220,
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
            width: 200,
            child: DropdownMenu<String?>(
              width: 200,
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
            width: 260,
            child: Row(
              children: [
                Text('${yearRange.start.round()}', style: Theme.of(context).textTheme.bodySmall),
                Expanded(
                  child: RangeSlider(
                    min: minYear.toDouble(),
                    max: maxYear.toDouble(),
                    values: yearRange,
                    onChanged: onYearRangeChanged,
                  ),
                ),
                Text('${yearRange.end.round()}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text(
            '$resultCount of $totalCount entries',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TableView extends StatelessWidget {
  const _TableView({
    required this.entries,
    required this.sortField,
    required this.ascending,
    required this.onSort,
  });

  final List<PriceEntry> entries;
  final _SortField sortField;
  final bool ascending;
  final ValueChanged<_SortField> onSort;

  static const _flexes = [1, 2, 3, 1, 2, 1, 1];

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
              _headerCell('Qty', _SortField.quantity, flex: _flexes[3]),
              _headerCell('Price', _SortField.price, flex: _flexes[4]),
              _headerCell('Pg', _SortField.page, flex: _flexes[5]),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: entries.length,
            itemExtent: 52,
            itemBuilder: (context, i) => _EntryRow(entry: entries[i], flexes: _flexes),
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
                  style: TextStyle(fontWeight: active ? FontWeight.bold : FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (active)
                Icon(ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.flexes});
  final PriceEntry entry;
  final List<int> flexes;

  String get _quantity {
    final parts = [entry.unit1, entry.unit2, entry.unit3]
        .where((v) => v != null)
        .map((v) => v! % 1 == 0 ? v.toInt().toString() : v.toString());
    return parts.isEmpty ? '—' : parts.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _edit(context),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(flex: flexes[0], child: Text('${entry.year ?? ''}')),
            Expanded(flex: flexes[1], child: Text(entry.placeLabel, overflow: TextOverflow.ellipsis)),
            Expanded(flex: flexes[2], child: Text(entry.categoryLabel, overflow: TextOverflow.ellipsis)),
            Expanded(flex: flexes[3], child: Text(_quantity, overflow: TextOverflow.ellipsis)),
            Expanded(flex: flexes[4], child: Text(entry.priceLabel)),
            Expanded(flex: flexes[5], child: Text('${entry.page ?? ''}')),
            SizedBox(
              width: 48,
              child: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _edit(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final app = context.read<AppController>();
    final updated = await showEditEntryDialog(context, entry: entry, repository: app.repository);
    if (updated != null) app.applyEdit(updated);
  }
}

class _CompactList extends StatelessWidget {
  const _CompactList({required this.entries});
  final List<PriceEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = entries[i];
        return Card(
          child: ListTile(
            title: Text('${e.categoryLabel} — ${e.priceLabel}'),
            subtitle: Text('${e.year ?? ''} · ${e.placeLabel}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final app = context.read<AppController>();
              final updated = await showEditEntryDialog(context, entry: e, repository: app.repository);
              if (updated != null) app.applyEdit(updated);
            },
          ),
        );
      },
    );
  }
}
