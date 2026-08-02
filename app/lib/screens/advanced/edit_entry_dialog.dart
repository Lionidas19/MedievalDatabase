import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/database_repository.dart';
import '../../widgets/autocomplete_field.dart';

/// Opens the edit dialog and returns the saved entry, or null if cancelled.
Future<PriceEntry?> showEditEntryDialog(
  BuildContext context, {
  required PriceEntry entry,
  required DatabaseRepository repository,
}) {
  return showDialog<PriceEntry>(
    context: context,
    builder: (_) => EditEntryDialog(entry: entry, repository: repository),
  );
}

class EditEntryDialog extends StatefulWidget {
  const EditEntryDialog({super.key, required this.entry, required this.repository});
  final PriceEntry entry;
  final DatabaseRepository repository;

  @override
  State<EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<EditEntryDialog> {
  late PriceEntry _e;
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
  late String _measure1Text;
  late String _measure2Text;
  late String _measure3Text;
  late String _valuationText;
  late String _outputXText;
  late String _outputYText;

  @override
  void initState() {
    super.initState();
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
    _measure1Text = _e.measure1Name ?? '';
    _measure2Text = _e.measure2Name ?? '';
    _measure3Text = _e.measure3Name ?? '';
    _valuationText = _e.valuationUnitName ?? '';
    _outputXText = _e.outputXName ?? '';
    _outputYText = _e.outputYName ?? '';
  }

  DatabaseRepository get _repo => widget.repository;

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
    _e.multiplierMeasureId = repo.resolveOrCreateMultiplierMeasure(_multiplierMeasureText);
    _e.sourceId = repo.resolveOrCreateSource(_sourceText);
    _e.countryId = repo.resolveOrCreateCountry(_countryText);
    _e.coinTypeId = repo.resolveOrCreateCoinType(_coinTypeText);
    _e.measure1UnitId = repo.resolveOrCreateUnit(_measure1Text);
    _e.measure2UnitId = repo.resolveOrCreateUnit(_measure2Text);
    _e.measure3UnitId = repo.resolveOrCreateUnit(_measure3Text);
    _e.valuationUnitId = repo.resolveOrCreateUnit(_valuationText);
    _e.outputXUnitId = repo.resolveOrCreateUnit(_outputXText);
    _e.outputYUnitId = repo.resolveOrCreateUnit(_outputYText);

    Navigator.of(context).pop(_e);
  }

  @override
  Widget build(BuildContext context) {
    final repo = _repo;
    final unitNames = repo.units.map((u) => u.label).toList();
    final localityNames = repo.places().map((p) => p.label.split(',').first).toSet().toList();
    final countyNames = repo.counties.map((c) => c.label).toList();
    final categoryNames = repo.categories.map((c) => c.name).toList();
    final subcategoryNames = <String>{
      for (final c in repo.categories) for (final s in repo.subcategoriesOf(c.id)) s.name,
    }.toList();
    final specificNames = <String>{
      for (final c in repo.categories)
        for (final s in repo.subcategoriesOf(c.id))
          for (final sp in repo.specificsOf(s.id)) sp.name,
    }.toList();
    final sourceNames = repo.sources.map((s) => s.label).toList();
    final countryNames = repo.countries.map((c) => c.label).toList();
    final coinTypeNames = repo.coinTypes.map((c) => c.label).toList();
    final timePeriodNames = repo.timePeriods.map((t) => t.label).toList();
    final multiplierMeasureNames = repo.multiplierMeasures.map((m) => m.label).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit entry #${_e.legacyEntryNo ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Location & time'),
                    _row([
                      Expanded(
                        child: AutocompleteField(
                          label: 'Locality',
                          initialValue: _localityText,
                          suggestions: localityNames,
                          onChanged: (v) => _localityText = v,
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'County',
                          initialValue: _countyText,
                          suggestions: countyNames,
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
                          suggestions: timePeriodNames,
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
                    _section('Category'),
                    _row([
                      Expanded(
                        child: AutocompleteField(
                          label: 'Category',
                          initialValue: _categoryText,
                          suggestions: categoryNames,
                          onChanged: (v) => _categoryText = v,
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Subcategory',
                          initialValue: _subcategoryText,
                          suggestions: subcategoryNames,
                          onChanged: (v) => _subcategoryText = v,
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Specific',
                          initialValue: _specificText,
                          suggestions: specificNames,
                          onChanged: (v) => _specificText = v,
                        ),
                      ),
                    ]),
                    _section('Quantity & price'),
                    _row([
                      Expanded(child: NumberField(label: 'Unit 1', initialValue: _e.unit1, onChanged: (v) => _e.unit1 = v?.toDouble())),
                      Expanded(child: NumberField(label: 'Unit 2', initialValue: _e.unit2, onChanged: (v) => _e.unit2 = v?.toDouble())),
                      Expanded(child: NumberField(label: 'Unit 3', initialValue: _e.unit3, onChanged: (v) => _e.unit3 = v?.toDouble())),
                    ]),
                    _row([
                      Expanded(
                        child: NumberField(
                          label: 'Multiplier / workers',
                          initialValue: _e.multiplierWorkers,
                          onChanged: (v) => _e.multiplierWorkers = v?.toDouble(),
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Multiplier measure',
                          initialValue: _multiplierMeasureText,
                          suggestions: multiplierMeasureNames,
                          onChanged: (v) => _multiplierMeasureText = v,
                        ),
                      ),
                    ]),
                    _row([
                      Expanded(child: NumberField(label: 'Pounds (£)', initialValue: _e.pounds, onChanged: (v) => _e.pounds = v?.toDouble())),
                      Expanded(child: NumberField(label: 'Shillings (s)', initialValue: _e.shillings, onChanged: (v) => _e.shillings = v?.toDouble())),
                      Expanded(child: NumberField(label: 'Pence (d)', initialValue: _e.pence, onChanged: (v) => _e.pence = v?.toDouble())),
                    ]),
                    TextFormField(
                      initialValue: _e.statusInfo,
                      decoration: const InputDecoration(labelText: 'Status / info'),
                      onChanged: (v) => _e.statusInfo = v,
                    ),
                    _section('Source'),
                    AutocompleteField(
                      label: 'Source citation',
                      initialValue: _sourceText,
                      suggestions: sourceNames,
                      onChanged: (v) => _sourceText = v,
                    ),
                    const SizedBox(height: 12),
                    _row([
                      Expanded(child: NumberField(label: 'Page', initialValue: _e.page, integer: true, onChanged: (v) => _e.page = v?.toInt())),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Country',
                          initialValue: _countryText,
                          suggestions: countryNames,
                          onChanged: (v) => _countryText = v,
                        ),
                      ),
                      Expanded(
                        child: AutocompleteField(
                          label: 'Coin type',
                          initialValue: _coinTypeText,
                          suggestions: coinTypeNames,
                          onChanged: (v) => _coinTypeText = v,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _e.information,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Information'),
                      onChanged: (v) => _e.information = v,
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Calculated / measure fields'),
                      subtitle: const Text('Unit conversions used for this entry\'s figures'),
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      children: [
                        _row([
                          Expanded(
                            child: AutocompleteField(
                              label: 'Measure 1',
                              initialValue: _measure1Text,
                              suggestions: unitNames,
                              onChanged: (v) => _measure1Text = v,
                            ),
                          ),
                          Expanded(
                            child: AutocompleteField(
                              label: 'Measure 2',
                              initialValue: _measure2Text,
                              suggestions: unitNames,
                              onChanged: (v) => _measure2Text = v,
                            ),
                          ),
                          Expanded(
                            child: AutocompleteField(
                              label: 'Measure 3',
                              initialValue: _measure3Text,
                              suggestions: unitNames,
                              onChanged: (v) => _measure3Text = v,
                            ),
                          ),
                        ]),
                        _row([
                          Expanded(
                            child: AutocompleteField(
                              label: 'Valuation unit',
                              initialValue: _valuationText,
                              suggestions: unitNames,
                              onChanged: (v) => _valuationText = v,
                            ),
                          ),
                          Expanded(
                            child: NumberField(label: 'Total grams', initialValue: _e.totalGrams, onChanged: (v) => _e.totalGrams = v?.toDouble()),
                          ),
                        ]),
                        _row([
                          Expanded(
                            child: AutocompleteField(
                              label: 'Output X unit',
                              initialValue: _outputXText,
                              suggestions: unitNames,
                              onChanged: (v) => _outputXText = v,
                            ),
                          ),
                          Expanded(
                            child: NumberField(label: 'Output X value', initialValue: _e.outputXValue, onChanged: (v) => _e.outputXValue = v?.toDouble()),
                          ),
                        ]),
                        _row([
                          Expanded(
                            child: AutocompleteField(
                              label: 'Chosen output Y unit',
                              initialValue: _outputYText,
                              suggestions: unitNames,
                              onChanged: (v) => _outputYText = v,
                            ),
                          ),
                          Expanded(
                            child: NumberField(label: 'Val grams', initialValue: _e.valGrams, onChanged: (v) => _e.valGrams = v?.toDouble()),
                          ),
                        ]),
                        _row([
                          Expanded(child: NumberField(label: 'Sales calc', initialValue: _e.salesCalc, onChanged: (v) => _e.salesCalc = v?.toDouble())),
                          Expanded(child: NumberField(label: 'Price in pence', initialValue: _e.priceInPence, onChanged: (v) => _e.priceInPence = v?.toDouble())),
                        ]),
                        _row([
                          Expanded(child: NumberField(label: 'Total sale in pence', initialValue: _e.totalSaleInPence, onChanged: (v) => _e.totalSaleInPence = v?.toDouble())),
                          Expanded(child: NumberField(label: 'Pence per output Y', initialValue: _e.pencePerOutputY, onChanged: (v) => _e.pencePerOutputY = v?.toDouble())),
                        ]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('Save changes')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
