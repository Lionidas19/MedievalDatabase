import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A warm, parchment-and-ink palette that nods to the subject matter
/// (medieval price records) without tipping into pastiche.
class AppTheme {
  static const _seed = Color(0xFF7A5230); // aged leather brown
  static const _ink = Color(0xFF2B2118);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    ).copyWith(
      surface: const Color(0xFFFBF6EC),
      surfaceContainerLowest: const Color(0xFFFFFDF8),
      surfaceContainerLow: const Color(0xFFF6EFE0),
      surfaceContainer: const Color(0xFFF0E6D2),
      surfaceContainerHigh: const Color(0xFFE9DCC2),
      surfaceContainerHighest: const Color(0xFFE1D2B3),
    );
    return _themeFrom(scheme, _ink);
  }

  static ThemeData dark() {
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
    return _themeFrom(scheme, const Color(0xFFEFE6D6));
  }

  static ThemeData _themeFrom(ColorScheme scheme, Color textColor) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: textColor,
      displayColor: textColor,
    );
    final headingFont = GoogleFonts.spectralTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme.copyWith(
        headlineLarge: headingFont.headlineLarge?.copyWith(color: textColor),
        headlineMedium: headingFont.headlineMedium?.copyWith(color: textColor),
        headlineSmall: headingFont.headlineSmall?.copyWith(color: textColor),
        titleLarge: headingFont.titleLarge?.copyWith(color: textColor, fontWeight: FontWeight.w600),
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
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

/// Responsive breakpoints shared across the app.
class Breakpoints {
  static const compact = 640.0;
  static const medium = 1024.0;

  static bool isCompact(double width) => width < compact;
  static bool isMedium(double width) => width >= compact && width < medium;
  static bool isExpanded(double width) => width >= medium;
}
