import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/models/models.dart';
import 'package:price_explorer/screens/advanced/filter_bar.dart';
import 'package:price_explorer/screens/simple/facets.dart';

/// `Oxfordshire` and `Oxfordshire (?)` are two rows on his Places tab and two
/// counties in the database, and that is right: the hedge is his evidence
/// about which county a place sits in.
///
/// It is wrong in a filter. Picking `Oxfordshire` used to miss the 124 entries
/// recorded under the hedged spelling, silently, with the count beside the
/// button reporting the smaller number as though it were the answer.
void main() {
  PriceEntry at(String county) => PriceEntry(
        entryId: 'e-$county',
        year: 1275,
        county: county,
        locality: 'Skipton',
        category: 'Food',
      );

  group('the hedge comes off a county name', () {
    test('only when it is actually there, and only at the end', () {
      expect(bareCountyName('Oxfordshire (?)'), 'Oxfordshire');
      expect(bareCountyName('Oxfordshire'), 'Oxfordshire');
      expect(bareCountyName('Caernarfon North Wales (?)'),
          'Caernarfon North Wales');
      // Not a hedge: part of the name itself.
      expect(bareCountyName('Haburdenne (cod?)'), 'Haburdenne (cod?)');
      expect(bareCountyName('(?)'), '(?)');
    });
  });

  group('filtering by county', () {
    test('one option finds both spellings', () {
      const f = FilterState(county: 'Oxfordshire');
      expect(f.matches(at('Oxfordshire')), isTrue);
      expect(f.matches(at('Oxfordshire (?)')), isTrue);
      expect(f.matches(at('Yorkshire')), isFalse);
      expect(f.matches(at('Yorkshire (?)')), isFalse);
    });

    test('a county that exists only hedged is found under its bare name', () {
      // Six of the sixteen have no plain twin, so the bare name is the only
      // thing a reader could reasonably type.
      const f = FilterState(county: 'Caernarfon North Wales');
      expect(f.matches(at('Caernarfon North Wales (?)')), isTrue);
    });

    test('an entry with no county is not swept up by any of them', () {
      const f = FilterState(county: 'Oxfordshire');
      expect(f.matches(at('')), isFalse);
    });
  });

  group('counting what each option would find', () {
    test('both spellings count towards the one option', () {
      final counts = countFacets(
        [
          at('Oxfordshire'),
          at('Oxfordshire (?)'),
          at('Oxfordshire (?)'),
          at('Yorkshire'),
        ],
        const FacetQuery(startYear: 1270, endYear: 1291),
      );
      // Three, not one: the dropdown must not say an option is empty when
      // choosing it would return records.
      expect(counts.counties['Oxfordshire'], 3);
      expect(counts.counties['Oxfordshire (?)'], isNull);
      expect(counts.counties['Yorkshire'], 1);
    });

    test('the facet is still judged against the other filters, not itself',
        () {
      final counts = countFacets(
        [at('Oxfordshire (?)'), at('Yorkshire')],
        const FacetQuery(
            startYear: 1270, endYear: 1291, county: 'Oxfordshire'),
      );
      expect(counts.matching, 1);
      // Yorkshire still on offer, because changing only the county reaches it.
      expect(counts.counties['Yorkshire'], 1);
    });
  });
}
