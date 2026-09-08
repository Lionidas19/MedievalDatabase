/// Julian and Gregorian dates.
///
/// The records are Julian: England kept the Julian calendar until 1752, so a
/// date written in these accounts is a Julian one. Converting to the calendar
/// a modern reader uses shifts it by seven days in the thirteenth century.
///
/// This matters for very little of this database — 108 of 7,800 entries carry
/// a day of the month — but where a full date does exist, showing it in one
/// calendar while calling it the other would be quietly wrong.
///
/// It is *not* the calendar problem that affects every entry. See
/// [ladyDayCaveat].
library;

/// Which calendar a date is being expressed in.
enum Calendar {
  /// As written in the source.
  julian,

  /// As a modern reader would date the same day.
  gregorian,
}

extension CalendarLabel on Calendar {
  String get label => this == Calendar.julian ? 'Julian' : 'Gregorian';
}

/// A day, month and year, in whichever calendar the caller is holding.
class CalendarDate {
  const CalendarDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  String toString() =>
      '$day ${_monthNames[month - 1]} $year';

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}

/// Julian Day Number for a date in the Julian calendar.
int julianDayNumber(CalendarDate d) {
  final a = (14 - d.month) ~/ 12;
  final y = d.year + 4800 - a;
  final m = d.month + 12 * a - 3;
  return d.day + (153 * m + 2) ~/ 5 + 365 * y + y ~/ 4 - 32083;
}

/// The Gregorian date with the same Julian Day Number.
CalendarDate fromJulianDayNumber(int jdn) {
  final a = jdn + 32044;
  final b = (4 * a + 3) ~/ 146097;
  final c = a - 146097 * b ~/ 4;
  final d = (4 * c + 3) ~/ 1461;
  final e = c - 1461 * d ~/ 4;
  final m = (5 * e + 2) ~/ 153;
  return CalendarDate(
    100 * b + d - 4800 + m ~/ 10,
    m + 3 - 12 * (m ~/ 10),
    e - (153 * m + 2) ~/ 5 + 1,
  );
}

/// Converts a date as written in the records into the modern calendar.
CalendarDate julianToGregorian(CalendarDate julian) =>
    fromJulianDayNumber(julianDayNumber(julian));

/// How many days apart the two calendars are for [year] — 7 through the
/// thirteenth century, 8 from 1300, and so on.
int calendarOffsetDays(int year) {
  final julian = julianDayNumber(CalendarDate(year, 3, 1));
  final gregorian = fromJulianDayNumber(julian);
  final asJulian = CalendarDate(year, 3, 1);
  return gregorian.day - asJulian.day +
      (gregorian.month - asJulian.month) * 31;
}

const _monthNumbers = {
  'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3,
  'april': 4, 'apr': 4, 'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7,
  'august': 8, 'aug': 8, 'september': 9, 'sep': 9, 'sept': 9,
  'october': 10, 'oct': 10, 'november': 11, 'nov': 11, 'december': 12,
  'dec': 12,
};

/// Reads a full date out of an entry, or null when the record does not carry
/// one.
///
/// Most entries do not: the time-period column holds seasons and feast days as
/// often as months ('Michaelmas Term', 'Autumn'), and a day of the month is
/// recorded for barely one entry in seventy. Those are dated to a year and
/// nothing finer, and pretending otherwise would invent precision.
CalendarDate? parseRecordedDate(int? year, String? periodName, int? day) {
  if (year == null || day == null || periodName == null) return null;
  final month = _monthNumbers[periodName.trim().toLowerCase()];
  if (month == null) return null;
  if (day < 1 || day > 31) return null;
  return CalendarDate(year, month, day);
}

/// The calendar problem that actually affects this database.
///
/// Medieval English years commonly began on 25 March, not 1 January, so a
/// record written "January 1275" may be January 1276 by modern reckoning.
/// That shifts a *year*, not seven days, and it potentially touches every
/// entry rather than the hundred-odd with a full date.
///
/// Which convention Thorold Rogers used when he compiled these figures is a
/// question for the researcher, and until it is answered the app displays
/// years exactly as recorded and says so rather than silently adjusting them.
const ladyDayCaveat =
    'Years are shown exactly as the source records them. Medieval English '
    'years often began on 25 March, so a date recorded early in the year may '
    'fall in the following year by modern reckoning — this has not been '
    'adjusted for.';
