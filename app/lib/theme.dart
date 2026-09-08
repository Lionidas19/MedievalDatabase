import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import 'state/view_preferences.dart';

/// Spacing scale.
///
/// The views had 4, 8, 10, 12, 14, 16, 18, 20 and 24 scattered through them,
/// which is how a layout drifts out of alignment one padding at a time.
class Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
}

/// Figures that line up in a column.
///
/// Inter's default figures are proportional, so a column of prices staggers:
/// `1111` is visibly narrower than `8888`. In a table whose entire purpose is
/// comparing numbers down a column, that is not a small thing.
const tabularFigures = FontFeature.tabularFigures();

/// The app's palettes.
///
/// Parchment is the default and nods at the subject matter. The other two
/// exist for real situations rather than taste: a high-contrast set for
/// projectors and poor screens, and a neutral one for screenshots that have to
/// sit in a published paper without looking like a themed toy.
class AppTheme {
  /// Built themes, kept.
  ///
  /// `ColorScheme.fromSeed` runs Material's palette generation and each theme
  /// assembles two full [TextTheme]s; together they were the largest single
  /// cost of changing any setting, because `MaterialApp` rebuilds both the
  /// light and the dark theme every time. The twelve possible combinations are
  /// cheap to hold and never change during a session.
  static final _cache = <String, ThemeData>{};

  static ThemeData build({
    required ThemeVariant variant,
    required Brightness brightness,
    TableDensity density = TableDensity.comfortable,
  }) {
    final key = '${variant.name}.${brightness.name}.${density.name}';
    return _cache[key] ??= _build(variant, brightness, density);
  }

  static ThemeData _build(
      ThemeVariant variant, Brightness brightness, TableDensity density) {
    final (scheme, textColor) = switch (variant) {
      ThemeVariant.parchment => _parchment(brightness),
      ThemeVariant.contrast => _contrast(brightness),
      ThemeVariant.plain => _plain(brightness),
    };
    return _themeFrom(scheme, textColor, variant, density);
  }

  // ------------------------------------------------------------- palettes --

  static const _parchmentSeed = Color(0xFF7A5230); // aged leather brown
  static const _ink = Color(0xFF2B2118);

  static (ColorScheme, Color) _parchment(Brightness brightness) {
    if (brightness == Brightness.light) {
      final scheme = ColorScheme.fromSeed(
        seedColor: _parchmentSeed,
        brightness: Brightness.light,
      ).copyWith(
        surface: const Color(0xFFFBF6EC),
        surfaceContainerLowest: const Color(0xFFFFFDF8),
        surfaceContainerLow: const Color(0xFFF6EFE0),
        surfaceContainer: const Color(0xFFF0E6D2),
        surfaceContainerHigh: const Color(0xFFE9DCC2),
        surfaceContainerHighest: const Color(0xFFE1D2B3),
      );
      return (scheme, _ink);
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFC9A46A),
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF17140F),
      surfaceContainerLowest: const Color(0xFF0F0D0A),
      surfaceContainerLow: const Color(0xFF1C1812),
      surfaceContainer: const Color(0xFF221D15),
      surfaceContainerHigh: const Color(0xFF2A2419),
      surfaceContainerHighest: const Color(0xFF322B1E),
    );
    return (scheme, const Color(0xFFEFE6D6));
  }

  /// Maximum legibility.
  ///
  /// `contrastLevel: 1.0` asks Material to generate the scheme at its highest
  /// contrast ratio; the surface overrides then flatten the tinted greys it
  /// still produces, because a table read across a room needs plain white or
  /// plain black behind the text, not a shade of it.
  static (ColorScheme, Color) _contrast(Brightness brightness) {
    if (brightness == Brightness.light) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00458F),
        brightness: Brightness.light,
        contrastLevel: 1.0,
      ).copyWith(
        surface: const Color(0xFFFFFFFF),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF4F4F4),
        surfaceContainer: const Color(0xFFEDEDED),
        surfaceContainerHigh: const Color(0xFFE0E0E0),
        surfaceContainerHighest: const Color(0xFFD4D4D4),
        outline: const Color(0xFF3A3A3A),
        outlineVariant: const Color(0xFF767676),
        onSurfaceVariant: const Color(0xFF2A2A2A),
      );
      return (scheme, const Color(0xFF000000));
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF9FC7FF),
      brightness: Brightness.dark,
      contrastLevel: 1.0,
    ).copyWith(
      surface: const Color(0xFF000000),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF121212),
      surfaceContainer: const Color(0xFF1A1A1A),
      surfaceContainerHigh: const Color(0xFF262626),
      surfaceContainerHighest: const Color(0xFF333333),
      outline: const Color(0xFFC8C8C8),
      outlineVariant: const Color(0xFF8C8C8C),
      onSurfaceVariant: const Color(0xFFE4E4E4),
    );
    return (scheme, const Color(0xFFFFFFFF));
  }

  static (ColorScheme, Color) _plain(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5A6472),
      brightness: brightness,
    );
    return (
      scheme,
      brightness == Brightness.light
          ? const Color(0xFF1B1D20)
          : const Color(0xFFE6E8EB)
    );
  }

  // ---------------------------------------------------------------- build --

  static ThemeData _themeFrom(
    ColorScheme scheme,
    Color textColor,
    ThemeVariant variant,
    TableDensity density,
  ) {
    // fontFamily on the ThemeData itself, not only on the text styles: the
    // web engine downloads Roboto as its fallback for anything left on the
    // default family, which is a network request an offline app should not be
    // making.
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Segoe UI', 'Helvetica', 'Arial'],
    );

    // Both families ship with the app rather than being fetched from Google at
    // startup — see pubspec.yaml. The fallbacks are named anyway: a font asset
    // can fail to decode, and silently rendering nothing would be worse than
    // rendering in the system's own sans.
    final textTheme = base.textTheme
        .apply(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['Segoe UI', 'Helvetica', 'Arial'],
        )
        .apply(bodyColor: textColor, displayColor: textColor);

    // Only Parchment mixes a serif in. The other two are chosen for occasions
    // where the type should not draw attention to itself.
    final headingFont = variant == ThemeVariant.parchment
        ? base.textTheme.apply(
            fontFamily: 'Spectral',
            fontFamilyFallback: const ['Georgia', 'Times New Roman'],
          )
        : textTheme;

    final compact = density == TableDensity.compact;

    // One decoration for every control that looks like a field.
    //
    // A DropdownMenu does not inherit inputDecorationTheme — it carries its
    // own — so without handing it the same object the dropdowns and the text
    // boxes beside them ended up with different corners, fills and heights on
    // the same row.
    final fieldDecoration = InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: compact ? 8 : 12,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      visualDensity:
          compact ? VisualDensity.compact : VisualDensity.standard,
      textTheme: textTheme.copyWith(
        headlineLarge: headingFont.headlineLarge?.copyWith(color: textColor),
        headlineMedium: headingFont.headlineMedium?.copyWith(color: textColor),
        headlineSmall: headingFont.headlineSmall?.copyWith(color: textColor),
        titleLarge: headingFont.titleLarge
            ?.copyWith(color: textColor, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        titleTextStyle: headingFont.titleLarge?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
      ),
      inputDecorationTheme: fieldDecoration,
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: fieldDecoration,
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
            ),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        dataRowColor: WidgetStatePropertyAll(scheme.surfaceContainerLowest),
        dividerThickness: 0.6,
      ),
    );
  }
}

/// Lets a mouse drag the view the way a finger would.
///
/// Flutter leaves the mouse out of [dragDevices] on purpose: on most pages a
/// click-drag means selecting text, not panning. This table is the case the
/// default does not fit. At the fullest detail level it is some three thousand
/// pixels wide inside a window half that, and the only ways to reach the far
/// side were a shift-wheel most people never learn and a scrollbar three
/// pixels tall.
///
/// A drag still loses the gesture arena to anything that claims the pointer
/// first, so a click on a row opens it and a drag inside a text field selects
/// text, both unchanged.
class DragToPanScrollBehavior extends MaterialScrollBehavior {
  const DragToPanScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        ...super.dragDevices,
        PointerDeviceKind.mouse,
      };
}

/// Responsive breakpoints shared across the app.
///
/// Width alone was not enough. A thirteen-inch laptop is wide enough for the
/// full table and yet has barely six hundred pixels of height once the browser
/// has taken its share — and on a table, height is what you are actually
/// looking at. Every pixel of toolbar is a row of records you cannot see.
class Breakpoints {
  static const compact = 640.0;
  static const medium = 1024.0;

  /// Below this, horizontal room is tight enough that a summary should say
  /// less rather than wrap onto a second line.
  static const narrow = 1200.0;

  /// Below this height, vertical space is the scarce thing: a 1280x800 laptop
  /// screen leaves about 620px of page once the browser's own furniture is
  /// accounted for.
  static const short = 760.0;

  static bool isCompact(double width) => width < compact;
  static bool isMedium(double width) => width >= compact && width < medium;
  static bool isExpanded(double width) => width >= medium;
  static bool isNarrow(double width) => width < narrow;
  static bool isShort(double height) => height < short;
}
