/// How much of the database the reader wants put in front of them, plus the
/// appearance choices that go with it.
///
/// The brief names three audiences, and they are not three levels of skill so
/// much as three different questions:
///
///  1. someone who wants "what did glass cost in 1275" and an average to
///     answer it;
///  2. a worldbuilder or academic who wants the specific entries, their
///     sources, and control over the unit the price is expressed in;
///  3. a researcher who knows more about a given record than the database does
///     and has come to correct it.
///
/// One reader is all three on different days, so this is a setting rather than
/// a mode chosen once. It is deliberately a single setting shared by every
/// screen: a reader who asked for "everything" in the table has not asked to
/// go back to basics in the editor.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../services/preference_store.dart';

/// How much of each record to show.
enum DetailLevel { basics, detailed, everything }

extension DetailLevelLabel on DetailLevel {
  String get label => switch (this) {
        DetailLevel.basics => 'Basics',
        DetailLevel.detailed => 'More detail',
        DetailLevel.everything => 'Everything',
      };

  /// Who this level is for, in the brief's own terms.
  String get description => switch (this) {
        DetailLevel.basics =>
          'A plain answer: when, where, what, what it cost, and the price per '
              'unit. Nothing else.',
        DetailLevel.detailed =>
          'Adds the recorded quantities, the time of year, and the page each '
              'entry was read off.',
        DetailLevel.everything =>
          'Every recorded field, the measures behind each figure, and how the '
              'calculation reached its answer.',
      };

  bool get atLeastDetailed => index >= DetailLevel.detailed.index;
  bool get isEverything => this == DetailLevel.everything;
}

/// What the Explorer gathers rows under.
///
/// Grouping is not decoration here. Grouping by the kind of unit a good was
/// measured in makes visible *why* entries drop out of an average, which is
/// otherwise only explained in a footnote under the result.
enum GroupBy { none, year, county, category, dimension }

extension GroupByLabel on GroupBy {
  String get label => switch (this) {
        GroupBy.none => 'No grouping',
        GroupBy.year => 'By year',
        GroupBy.county => 'By county',
        GroupBy.category => 'By category',
        GroupBy.dimension => 'By kind of measure',
      };
}

/// The palettes on offer.
enum ThemeVariant { parchment, contrast, plain }

extension ThemeVariantLabel on ThemeVariant {
  String get label => switch (this) {
        ThemeVariant.parchment => 'Parchment',
        ThemeVariant.contrast => 'High contrast',
        ThemeVariant.plain => 'Plain',
      };

  String get description => switch (this) {
        ThemeVariant.parchment => 'Warm leather and ink, the default.',
        ThemeVariant.contrast =>
          'Maximum legibility — for projectors, poor screens and tired eyes.',
        ThemeVariant.plain =>
          'Neutral greys, for screenshots that have to sit in a paper.',
      };
}

/// Row height in the Explorer.
enum TableDensity { comfortable, compact }

extension TableDensityLabel on TableDensity {
  String get label =>
      this == TableDensity.comfortable ? 'Comfortable' : 'Compact';

  /// Pixel height of one table row.
  double get rowHeight => this == TableDensity.comfortable ? 52 : 38;
}

const _kDetail = 'detailLevel';
const _kGroupBy = 'groupBy';
const _kThemeMode = 'themeMode';
const _kVariant = 'themeVariant';
const _kDensity = 'density';
const _kGregorian = 'showGregorian';

/// Appearance and detail settings, remembered between visits.
///
/// These live in ordinary browser storage rather than the OPFS file the
/// database uses. They are preferences, not work: losing them costs a reader
/// four clicks, so they do not deserve the machinery that protects edits.
class ViewPreferences extends ChangeNotifier {
  ViewPreferences() {
    _load();
  }

  DetailLevel _detailLevel = DetailLevel.basics;
  GroupBy _groupBy = GroupBy.none;
  ThemeMode _themeMode = ThemeMode.system;
  ThemeVariant _variant = ThemeVariant.parchment;
  TableDensity _density = TableDensity.comfortable;

  /// Whether to show the modern equivalent alongside a recorded date.
  ///
  /// The brief asks for a Julian/Gregorian tickbox. It applies to far less of
  /// the database than one would expect — 108 entries of 7,800 carry a day of
  /// the month, and a bare year is the same number in both calendars — so this
  /// governs display of full dates rather than filtering.
  bool _showGregorian = true;

  DetailLevel get detailLevel => _detailLevel;
  GroupBy get groupBy => _groupBy;
  ThemeMode get themeMode => _themeMode;
  ThemeVariant get variant => _variant;
  TableDensity get density => _density;
  bool get showGregorian => _showGregorian;

  set detailLevel(DetailLevel v) => _set(() => _detailLevel = v, _kDetail, v.name);
  set groupBy(GroupBy v) => _set(() => _groupBy = v, _kGroupBy, v.name);
  set themeMode(ThemeMode v) => _set(() => _themeMode = v, _kThemeMode, v.name);
  set variant(ThemeVariant v) => _set(() => _variant = v, _kVariant, v.name);
  set density(TableDensity v) => _set(() => _density = v, _kDensity, v.name);
  set showGregorian(bool v) =>
      _set(() => _showGregorian = v, _kGregorian, '$v');

  void _set(VoidCallback apply, String key, String value) {
    apply();
    writePreference(key, value);
    notifyListeners();
  }

  void _load() {
    T pick<T>(String key, List<T> values, String Function(T) name, T fallback) {
      final stored = readPreference(key);
      if (stored == null) return fallback;
      for (final v in values) {
        if (name(v) == stored) return v;
      }
      return fallback;
    }

    _detailLevel = pick(_kDetail, DetailLevel.values, (v) => v.name,
        DetailLevel.basics);
    _groupBy = pick(_kGroupBy, GroupBy.values, (v) => v.name, GroupBy.none);
    _themeMode =
        pick(_kThemeMode, ThemeMode.values, (v) => v.name, ThemeMode.system);
    _variant = pick(
        _kVariant, ThemeVariant.values, (v) => v.name, ThemeVariant.parchment);
    _density = pick(
        _kDensity, TableDensity.values, (v) => v.name, TableDensity.comfortable);
    _showGregorian = readPreference(_kGregorian) != 'false';
  }
}
