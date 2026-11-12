import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';
import 'package:price_explorer/screens/advanced/filter_bar.dart';
import 'package:price_explorer/widgets/record_notes.dart';

/// Finding one record, and reading what it says beyond its price.
void main() {
  PriceEntry entry({
    int no = 3482,
    String? status,
    String? food,
    String? information,
    double? pounds,
    double? shillings,
    double? pence = 4,
  }) =>
      PriceEntry(
        entryId: 'e$no',
        legacyEntryNo: no,
        year: 1279,
        locality: 'Thorney',
        category: 'Other',
        subcategory: 'Other',
        specific: 'Other',
        statusInfo: status,
        food: food,
        information: information,
        pounds: pounds,
        shillings: shillings,
        pence: pence,
      );

  bool finds(String search, PriceEntry e) =>
      FilterState(search: search).passesSearch(e);

  group('search by entry number', () {
    test('a bare number finds that entry and not its neighbours', () {
      expect(finds('3482', entry()), isTrue);
      expect(finds('3482', entry(no: 3483)), isFalse);
      // Exact, not a prefix: typing 348 should not mean "anything from 3480".
      expect(finds('348', entry()), isFalse);
    });

    test('the prefixed forms mean the entry alone', () {
      for (final q in ['#3482', 'entry 3482', 'Entry 3482', 'no. 3482']) {
        expect(finds(q, entry()), isTrue, reason: q);
      }
      // "44 poles" holds a 44, but "#44" asks for entry 44.
      expect(finds('#44', entry(status: '44 poles')), isFalse);
    });

    test('a bare number still searches the notes', () {
      expect(finds('44', entry(status: '44 poles')), isTrue);
    });

    test('a run of entries', () {
      expect(finds('3480-3490', entry()), isTrue);
      expect(finds('3480 – 3490', entry()), isTrue);
      expect(finds('3480-3481', entry()), isFalse);
    });
  });

  group('notes', () {
    test('none, when the record says nothing more', () {
      expect(recordNotes(entry()), isEmpty);
      expect(recordNotes(entry(status: '  ', food: '')), isEmpty);
    });

    test('each field the record fills, labelled and trimmed', () {
      expect(
        recordNotes(entry(
            status: 'Exchange rates ', food: '1 qtr', information: 'Pannus')),
        [
          ('Note', 'Exchange rates'),
          ('Paid in food', '1 qtr'),
          ('Information', 'Pannus'),
        ],
      );
    });
  });

  // A dash is silence, and nought is a claim. The row used to show a dash
  // here beside "0" and "£0.00" for the same record.
  test('a recorded nought reads as one, and a missing price as a dash', () {
    expect(entry(pence: 0).priceLabel, '0d');
    expect(entry(pence: null).priceLabel, '—');
    expect(entry(shillings: 3, pence: 4).priceLabel, '3s 4d');
  });
}
