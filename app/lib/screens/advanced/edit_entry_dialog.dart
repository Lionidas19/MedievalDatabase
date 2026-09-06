import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/calendar.dart';
import '../../services/database_repository.dart';
import '../../services/pricing.dart';
import '../../state/view_preferences.dart';
import '../../theme.dart';
import '../../widgets/autocomplete_field.dart';

/// Opens the edit dialog and returns the saved entry, or null if cancelled.
Future<PriceEntry?> showEditEntryDialog(
  BuildContext context, {
  required PriceEntry entry,
  required DatabaseRepository repository,
  bool isNew = false,
  VoidCallback? onDelete,
}) {
  return showDialog<PriceEntry>(
    context: context,
    barrierDismissible: !isNew,
    builder: (_) => EditEntryDialog(
      entry: entry,
      repository: repository,
      isNew: isNew,
      onDelete: onDelete,
    ),
  );
}

class EditEntryDialog extends StatefulWidget {
  const EditEntryDialog({
    super.key,
    required this.entry,
    required this.repository,
    this.isNew = false,
    this.onDelete,
  });

  final PriceEntry entry;
  final DatabaseRepository repository;

  /// A blank entry that has just been created. Cancelling discards it, so the
  /// dialog cannot be dismissed by tapping outside it.
  final bool isNew;

  /// Called after the editor confirms deletion. Absent means undeletable.
  final VoidCallback? onDelete;

  @override
  State<EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<EditEntryDialog> {
  late PriceEntry _e;

  // Free-text buffers for the lookup-backed fields. They are resolved to (or
  // created in) their lookup tables on save.
  late String _localityText;
  late String _countyText;
  late String _categoryText;
  late String _subcategoryText;
  late String _specificText;
  late String _timePeriodText;
  late String _multiplierMeasureText;
  late String _sourceText;
  late String _countryText;
  late String _coinTypeText;

  DatabaseRepository get _repo => widget.repository;

  // Suggestion lists, gathered once.
  //
  // These were rebuilt inside build(), and building the 'specific' list alone
  // runs a query per category and per subcategory — a hundred round trips to
  // sqlite every time a keystroke in a number field called setState. The
  // database cannot change while this dialog is open, so once is enough.
  late final List<String> _measureNames;
  late final List<String> _standardNames;
  late final List<String> _localityNames;
  late final List<String> _countyNames;
  late final List<String> _categoryNames;
  late final List<String> _subcategoryNames;
  late final List<String> _specificNames;
  late final List<String> _sourceNames;
  late final List<String> _countryNames;
  late final List<String> _coinTypeNames;
  late final List<String> _timePeriodNames;
  late final List<String> _multiplierMeasureNames;

  @override
  void initState() {
    super.initState();
    final repo = widget.repository;
    _measureNames = repo.measures.map((m) => m.name).toList();
    _standardNames = repo.standards.map((s) => s.name).toList();
    _localityNames =
        repo.places().map((p) => p.label.split(',').first).toSet().toList();
    _countyNames = repo.counties.map((c) => c.label).toList();
    _categoryNames = repo.categories.map((c) => c.name).toList();
    _subcategoryNames = <String>{
      for (final c in repo.categories)
        for (final s in repo.subcategoriesOf(c.id)) s.name,
    }.toList();
    _specificNames = <String>{
      for (final c in repo.categories)
        for (final s in repo.subcategoriesOf(c.id))
          for (final sp in repo.specificsOf(s.id)) sp.name,
    }.toList();
    _sourceNames = repo.sources.map((s) => s.label).toList();
    _countryNames = repo.countries.map((c) => c.label).toList();
    _coinTypeNames = repo.coinTypes.map((c) => c.label).toList();
    _timePeriodNames = repo.timePeriods.map((t) => t.label).toList();
    _multiplierMeasureNames =
        repo.multiplierMeasures.map((m) => m.label).toList();

    _e = widget.entry.copy();
    _localityText = _e.locality ?? '';
    _countyText = _e.county ?? '';
    _categoryText = _e.category ?? '';
    _subcategoryText = _e.subcategory ?? '';
    _specificText = _e.specific ?? '';
    _timePeriodText = _e.timePeriodName ?? '';
    _multiplierMeasureText = _e.multiplierMeasureName ?? '';
    _sourceText = _e.sourceCitation ?? '';
    _countryText = _e.countryName ?? '';
    _coinTypeText = _e.coinTypeName ?? '';
  }

  void _save() {
    final repo = _repo;
    _e.placeId = repo.resolveOrCreatePlace(
      _localityText.trim().isEmpty ? '—' : _localityText,
      county: _countyText,
    );
    if (_categoryText.trim().isNotEmpty) {
      _e.specificId = repo.resolveOrCreateSpecificChain(
        _categoryText,
        _subcategoryText.trim().isEmpty ? 'Unspecified' : _subcategoryText,
        _specificText.trim().isEmpty ? 'Unspecified' : _specificText,
      );
    }
    _e.timePeriodId = repo.resolveOrCreateTimePeriod(_timePeriodText);
    _e.multiplierMeasureId =
        repo.resolveOrCreateMultiplierMeasure(_multiplierMeasureText);
    _e.sourceId = repo.resolveOrCreateSource(_sourceText);
    _e.countryId = repo.resolveOrCreateCountry(_countryText);
    _e.coinTypeId = repo.resolveOrCreateCoinType(_coinTypeText);
    Navigator.of(context).pop(_e);
  }

  /// Measures and standards are separate vocabularies; picking from the wrong
  /// one is the single easiest way to corrupt a figure, so each field is bound
  /// to exactly one of them.
  Widget _measureField(String label, MetricItem? current,
      List<String> suggestions, ValueChanged<MetricItem?> onChanged) {
    return _metricField(label, current, suggestions,
        (name) => _repo.resolveOrCreateMeasure(name), onChanged);
  }

  Widget _standardField(String label, MetricItem? current,
      List<String> suggestions, ValueChanged<MetricItem?> onChanged) {
    return _metricField(label, current, suggestions,
        (name) => _repo.resolveOrCreateStandard(name), onChanged);
  }

  Widget _metricField(
    String label,
    MetricItem? current,
    List<String> suggestions,
    MetricItem? Function(String) resolve,
    ValueChanged<MetricItem?> onChanged,
  ) {
    // A unit with no metric value cannot contribute to any figure. Saying so
    // here is far kinder than letting the reader wonder why a total is zero.
    final warning = current != null && !current.isResolved
        ? 'No metric value on record — contributes 0'
        : null;
    return AutocompleteField(
      label: label,
      initialValue: current?.name ?? '',
      suggestions: suggestions,
      helperText: warning,
      onChanged: (text) => setState(() => onChanged(resolve(text))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<ViewPreferences>();
    final level = prefs.detailLevel;
    final detailed = level.atLeastDetailed;
    final everything = level.isEverything;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.xl, Spacing.lg, Spacing.md, Spacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.isNew
                              ? 'New entry #${_e.legacyEntryNo ?? ''}'
                              : 'Edit entry #${_e.legacyEntryNo ?? ''}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  // The same setting the table uses, offered here as well.
                  // Somebody who came to correct one field should not have to
                  // go back out to the toolbar to be shown that field.
                  Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Show',
                          style: Theme.of(context).textTheme.labelMedium),
                      for (final l in DetailLevel.values)
                        ChoiceChip(
                          label: Text(l.label),
                          selected: level == l,
                          showCheckmark: false,
                          onSelected: (_) => prefs.detailLevel = l,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Location & time'),
                    _row([
                      Expanded(
                        child: AutocompleteField(
                          label: 'Locality',
                          initialValue: _localityText,
                          suggestions: _localityNames,
                          onChanged: (v) => _localityText = v,
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'County',
                          initialValue: _countyText,
                          suggestions: _countyNames,
                          onChanged: (v) => _countyText = v,
                        ),
                      ),
                    ]),
                    _row([
                      Expanded(
                        child: NumberField(
                          label: 'Year',
                          initialValue: _e.year,
                          integer: true,
                          onChanged: (v) => _e.year = v?.toInt(),
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Time period',
                          initialValue: _timePeriodText,
                          suggestions: _timePeriodNames,
                          helperText: 'Month, season or feast',
                          onChanged: (v) => _timePeriodText = v,
                        ),
                      ),
                      Expanded(
                        child: NumberField(
                          label: 'Day of month',
                          initialValue: _e.dayOfMonth,
                          integer: true,
                          onChanged: (v) => _e.dayOfMonth = v?.toInt(),
                        ),
                      ),
                    ]),
                    _RecordedDate(
                      year: _e.year,
                      periodName: _timePeriodText,
                      day: _e.dayOfMonth,
                      showGregorian: prefs.showGregorian,
                    ),
                    _section('Category'),
                    _row([
                      Expanded(
                        child: AutocompleteField(
                          label: 'Category',
                          initialValue: _categoryText,
                          suggestions: _categoryNames,
                          onChanged: (v) => _categoryText = v,
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Subcategory',
                          initialValue: _subcategoryText,
                          suggestions: _subcategoryNames,
                          onChanged: (v) => _subcategoryText = v,
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Specific',
                          initialValue: _specificText,
                          suggestions: _specificNames,
                          onChanged: (v) => _specificText = v,
                        ),
                      ),
                    ]),
                    if (detailed) ...[
                      _section('Quantity'),
                      _row([
                        Expanded(
                          child: NumberField(
                            label: 'Unit 1',
                            initialValue: _e.unit1,
                            onChanged: (v) =>
                                setState(() => _e.unit1 = v?.toDouble()),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _measureField('Measure 1', _e.measure1,
                              _measureNames, (m) => _e.measure1 = m),
                        ),
                      ]),
                      _row([
                        Expanded(
                          child: NumberField(
                            label: 'Unit 2',
                            initialValue: _e.unit2,
                            onChanged: (v) =>
                                setState(() => _e.unit2 = v?.toDouble()),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _measureField('Measure 2', _e.measure2,
                              _measureNames, (m) => _e.measure2 = m),
                        ),
                      ]),
                      _row([
                        Expanded(
                          child: NumberField(
                            label: 'Unit 3',
                            initialValue: _e.unit3,
                            onChanged: (v) =>
                                setState(() => _e.unit3 = v?.toDouble()),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _measureField('Measure 3', _e.measure3,
                              _measureNames, (m) => _e.measure3 = m),
                        ),
                      ]),
                    ],
                    if (everything)
                      _row([
                        Expanded(
                          child: NumberField(
                            label: 'Multiplier / workers',
                            initialValue: _e.multiplierWorkers,
                            onChanged: (v) => setState(
                                () => _e.multiplierWorkers = v?.toDouble()),
                          ),
                        ),
                        Expanded(
                          child: AutocompleteField(
                            label: 'Multiplier measure',
                            initialValue: _multiplierMeasureText,
                            suggestions: _multiplierMeasureNames,
                            onChanged: (v) => _multiplierMeasureText = v,
                          ),
                        ),
                      ]),
                    _section('Price as recorded'),
                    Text(
                      'Often a price per valuation measure rather than a total '
                      '— like an hourly wage, not a pay slip.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Spacing.md),
                    _row([
                      Expanded(
                        child: NumberField(
                          label: 'Pounds (£)',
                          initialValue: _e.pounds,
                          onChanged: (v) =>
                              setState(() => _e.pounds = v?.toDouble()),
                        ),
                      ),
                      Expanded(
                        child: NumberField(
                          label: 'Shillings (s)',
                          initialValue: _e.shillings,
                          onChanged: (v) =>
                              setState(() => _e.shillings = v?.toDouble()),
                        ),
                      ),
                      Expanded(
                        child: NumberField(
                          label: 'Pence (d)',
                          initialValue: _e.pence,
                          onChanged: (v) =>
                              setState(() => _e.pence = v?.toDouble()),
                        ),
                      ),
                    ]),
                    if (detailed)
                      _row([
                        Expanded(
                          child: _measureField(
                              'Valuation measure',
                              _e.valuationMeasure,
                              _measureNames,
                              (m) => _e.valuationMeasure = m),
                        ),
                      ]),
                    if (everything) ...[
                      _section('Output units'),
                      Text(
                        'Drawn from the Standards vocabulary, not Measures. '
                        'Output X is a data correction; output Y is only the '
                        'default the reader sees first.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: Spacing.md),
                      _row([
                        Expanded(
                          child: _standardField('Output X', _e.outputX,
                              _standardNames, (s) => _e.outputX = s),
                        ),
                        Expanded(
                          child: _standardField('Output Y (default)',
                              _e.outputY, _standardNames, (s) => _e.outputY = s),
                        ),
                      ]),
                    ],
                    const SizedBox(height: Spacing.lg),
                    _CalculationPreview(entry: _e, level: level),
                    if (detailed) ...[
                      _section('Notes & source'),
                      TextFormField(
                        initialValue: _e.statusInfo,
                        decoration:
                            const InputDecoration(labelText: 'Status / info'),
                        onChanged: (v) => _e.statusInfo = v,
                      ),
                      const SizedBox(height: Spacing.md),
                      AutocompleteField(
                        label: 'Source citation',
                        initialValue: _sourceText,
                        suggestions: _sourceNames,
                        onChanged: (v) => _sourceText = v,
                      ),
                      const SizedBox(height: Spacing.md),
                      _row([
                        Expanded(
                          child: NumberField(
                            label: 'Page',
                            initialValue: _e.page,
                            integer: true,
                            onChanged: (v) => _e.page = v?.toInt(),
                          ),
                        ),
                        if (everything) ...[
                          Expanded(
                            child: AutocompleteField(
                              label: 'Country',
                              initialValue: _countryText,
                              suggestions: _countryNames,
                              onChanged: (v) => _countryText = v,
                            ),
                          ),
                          Expanded(
                            child: AutocompleteField(
                              label: 'Coin type',
                              initialValue: _coinTypeText,
                              suggestions: _coinTypeNames,
                              onChanged: (v) => _coinTypeText = v,
                            ),
                          ),
                        ],
                      ]),
                    ],
                    if (everything) ...[
                      const SizedBox(height: Spacing.md),
                      TextFormField(
                        initialValue: _e.food,
                        decoration: const InputDecoration(
                          labelText: 'Food',
                          helperText:
                              'Payment in kind, where it was not in coin',
                        ),
                        onChanged: (v) => _e.food = v,
                      ),
                      const SizedBox(height: Spacing.md),
                      TextFormField(
                        initialValue: _e.information,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(labelText: 'Information'),
                        onChanged: (v) => _e.information = v,
                      ),
                    ],
                    if (!everything) ...[
                      const SizedBox(height: Spacing.lg),
                      // A field that is not on screen is indistinguishable from
                      // a field the record does not have, so say which this is.
                      // Nothing hidden here is discarded on save.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.visibility_off_outlined,
                              size: 15, color: scheme.onSurfaceVariant),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              detailed
                                  ? 'Output units, the worker multiplier, coin '
                                      'type and free notes are hidden at this '
                                      'level. They are kept as they are when '
                                      'you save.'
                                  : 'Quantities, measures, source and notes are '
                                      'hidden at this level. They are kept as '
                                      'they are when you save.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                children: [
                  if (!widget.isNew && widget.onDelete != null)
                    TextButton.icon(
                      onPressed: _confirmDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      style:
                          TextButton.styleFrom(foregroundColor: scheme.error),
                      label: const Text('Delete entry'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(widget.isNew ? 'Discard' : 'Cancel'),
                  ),
                  const SizedBox(width: Spacing.sm),
                  FilledButton(
                    onPressed: _save,
                    child: Text(widget.isNew ? 'Add entry' : 'Save changes'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete entry #${_e.legacyEntryNo ?? ''}?'),
        content: const Text(
          'The entry is removed from the working copy. The source spreadsheet '
          'is untouched, so rebuilding the database brings it back — but any '
          'edits made here since would be lost.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop();
    widget.onDelete!();
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: children,
        ),
      );
}

/// Shows a full date in both calendars, where the record carries one.
///
/// The accounts are Julian, so a modern reader dating them from the page would
/// be seven days out. Barely one entry in seventy has a day of the month, so
/// this is usually absent — which is itself worth showing, since a year alone
/// is all most of these records give.
class _RecordedDate extends StatelessWidget {
  const _RecordedDate({
    required this.year,
    required this.periodName,
    required this.day,
    required this.showGregorian,
  });

  final int? year;
  final String? periodName;
  final int? day;

  /// Whether to name the modern equivalent as well. Off, the date is still
  /// labelled Julian — dropping the label as well would leave a date that
  /// looks modern and is seven days out.
  final bool showGregorian;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final julian = parseRecordedDate(year, periodName, day);
    final text = julian == null
        ? ladyDayCaveat
        : showGregorian
            ? '$julian in the Julian calendar the accounts use, which is '
                '${julianToGregorian(julian)} by modern reckoning.'
            : '$julian in the Julian calendar the accounts use.';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_outlined, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// Live view of what the entry currently computes to.
///
/// These were stored columns in the source spreadsheet. They are derived here,
/// so an editor can see immediately what a change to a quantity, measure or
/// price does — and, importantly, when it produces no answer at all.
class _CalculationPreview extends StatelessWidget {
  const _CalculationPreview({required this.entry, required this.level});
  final PriceEntry entry;

  /// How much of the working to show. The headline figure is the answer at
  /// every level; the intermediate steps are only of interest to somebody
  /// checking the arithmetic, and to everyone else they are noise around the
  /// number they came for.
  final DetailLevel level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = entry.calculate();
    final outputName = entry.outputY?.name ?? 'output unit';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Calculated', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          if (level.atLeastDetailed) ...[
            _line(context, 'Quantity in metric', formatPence(c.totalMetric)),
            _line(context, 'Price as pence', formatPence(c.priceInPence)),
            _line(context, 'Total sale in pence',
                formatPence(c.totalSaleInPence)),
          ],
          if (level.isEverything) ...[
            _line(context, 'Valuation count', formatPence(c.valuationCount)),
            _line(context, 'Output X value', formatPence(c.outputXValue)),
          ],
          _line(context, 'Pence per $outputName',
              formatPence(c.pencePerOutputY), emphasise: true),
          if (c.unresolvedMeasures > 0) ...[
            const SizedBox(height: 8),
            _note(
              context,
              '${c.unresolvedMeasures} measure'
              '${c.unresolvedMeasures == 1 ? '' : 's'} with a quantity but no '
              'metric value on record, so the total is an undercount.',
              scheme.error,
            ),
          ],
          if (!c.hasPricePerOutput) ...[
            const SizedBox(height: 8),
            _note(
              context,
              c.totalMetric == 0
                  ? 'No price per unit: nothing in this entry resolves to a '
                      'quantity to divide by. The source records the same gap.'
                  : 'No price per unit: the output or valuation unit has no '
                      'metric value on record.',
              scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value,
      {bool emphasise = false}) {
    final style = emphasise
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary)
        : Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text, Color color) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: color)),
          ),
        ],
      );
}
