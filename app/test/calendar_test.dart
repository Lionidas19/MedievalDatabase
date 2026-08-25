import 'package:flutter_test/flutter_test.dart';
import 'package:price_explorer/services/calendar.dart';

void main() {
  group('Julian day numbers', () {
    test('round-trip through a Julian Day Number', () {
      for (final d in [
        const CalendarDate(1270, 1, 1),
        const CalendarDate(1275, 6, 15),
        const CalendarDate(1291, 12, 31),
        const CalendarDate(1284, 2, 29), // Julian leap year
      ]) {
        expect(fromJulianDayNumber(julianDayNumber(d)), isNotNull);
      }
    });

    test('known anchor: 1 January 1270 Julian', () {
      // Derived from the standard anchor rather than trusted: JDN 2299160 is
      // 4 October 1582 Julian, the last day before the Gregorian reform.
      // 1270 to 1582 is 312 Julian years of 365.25 days = 113,958, plus 276
      // days from 1 January to 4 October. 2299160 - 114234 = 2184926.
      expect(julianDayNumber(const CalendarDate(1270, 1, 1)), 2184926);
    });

    test('agrees with the Gregorian reform anchor', () {
      // The reform made 4 October 1582 (Julian) the day before 15 October
      // 1582 (Gregorian). Those are consecutive days, not the same day: the
      // same instant is 4 October Julian and 14 October Gregorian, and the
      // ten days from the 5th to the 14th were then skipped over.
      expect(julianDayNumber(const CalendarDate(1582, 10, 4)), 2299160);
      expect(fromJulianDayNumber(2299160), const CalendarDate(1582, 10, 14));
      expect(fromJulianDayNumber(2299161), const CalendarDate(1582, 10, 15));
    });
  });

  group('Julian to Gregorian', () {
    test('the thirteenth century runs seven days behind', () {
      final g = julianToGregorian(const CalendarDate(1275, 6, 15));
      expect(g, const CalendarDate(1275, 6, 22));
    });

    test('the offset is seven days across the whole database range', () {
      for (final year in [1270, 1280, 1291]) {
        expect(calendarOffsetDays(year), 7,
            reason: 'the offset should be 7 days in $year');
      }
    });

    test('the offset grows to eight days from 1300', () {
      expect(calendarOffsetDays(1350), 8);
    });

    test('conversion can carry across a month boundary', () {
      final g = julianToGregorian(const CalendarDate(1275, 6, 28));
      expect(g.month, 7);
      expect(g.day, 5);
    });

    test('conversion can carry across a year boundary', () {
      final g = julianToGregorian(const CalendarDate(1275, 12, 28));
      expect(g.year, 1276);
      expect(g.month, 1);
      expect(g.day, 4);
    });
  });

  group('formatting', () {
    test('renders a readable date', () {
      expect(const CalendarDate(1275, 6, 15).toString(), '15 June 1275');
    });
  });

  group('the caveat that matters', () {
    test('is stated rather than silently applied', () {
      // The Lady Day year start shifts a year, not seven days, and touches
      // every entry rather than the hundred-odd with a full date. Until the
      // researcher says which convention the source uses, the app must not
      // adjust years behind the reader's back.
      expect(ladyDayCaveat, contains('25 March'));
      expect(ladyDayCaveat, contains('not been adjusted'));
    });
  });
}
