import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/app_controller.dart';
import 'state/view_preferences.dart';
import 'theme.dart';
import 'screens/home_shell.dart';
import 'widgets/focus_ring.dart';

void main() {
  _registerFontLicences();
  runApp(const PriceExplorerApp());
}

/// The reading typefaces are under the SIL Open Font Licence, which asks
/// that the licence travel with the fonts. Read lazily, when the licence
/// page is opened, so it costs nothing at startup.
void _registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final (name, file) in const [
      ('Atkinson Hyperlegible', 'AtkinsonHyperlegible-OFL.txt'),
      ('OpenDyslexic', 'OpenDyslexic-OFL.txt'),
    ]) {
      final text = await rootBundle.loadString('fonts/licences/$file');
      yield LicenseEntryWithLineBreaks([name], text);
    }
  });
}

class PriceExplorerApp extends StatelessWidget {
  const PriceExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ViewPreferences()),
        ChangeNotifierProvider(create: (_) => AppController()),
      ],
      // Only the settings that actually change the theme get to rebuild
      // MaterialApp, because rebuilding it rebuilds every screen under it.
      // Watching the whole of ViewPreferences meant that choosing a detail
      // level — which changes some columns and nothing else — tore down and
      // rebuilt the entire app. The screens that care about detail watch it
      // themselves, much further down.
      child:
          Selector<
            ViewPreferences,
            (ThemeMode, ThemeVariant, TableDensity, ReadingFont, TextSize, bool)
          >(
            selector: (_, prefs) => (
              prefs.themeMode,
              prefs.variant,
              prefs.density,
              prefs.font,
              prefs.textSize,
              prefs.widerSpacing,
            ),
            builder: (context, theme, _) {
              final (mode, variant, density, font, textSize, spacing) = theme;
              return MaterialApp(
                title: 'Medieval Price Explorer',
                debugShowCheckedModeBanner: false,
                // Switch the theme outright instead of cross-fading to it.
                //
                // MaterialApp otherwise animates the change over 200ms, and every
                // frame of that animation lerps a whole ThemeData — colour scheme,
                // every text style, every component theme — and rebuilds every
                // widget that read Theme.of. That is a dozen full rebuilds of a
                // dense table to perform a fade nobody asked for. Changing a
                // palette should land at once.
                themeAnimationDuration: Duration.zero,
                theme: AppTheme.build(
                  variant: variant,
                  brightness: Brightness.light,
                  density: density,
                  font: font,
                  widerSpacing: spacing,
                ),
                darkTheme: AppTheme.build(
                  variant: variant,
                  brightness: Brightness.dark,
                  density: density,
                  font: font,
                  widerSpacing: spacing,
                ),
                // The reader's text size on top of whatever the system already
                // asks for, not instead of it; and the keyboard's focus ring over
                // everything, dialogs included, which is why it is here and not
                // in a screen.
                //
                builder: (context, child) {
                  final media = MediaQuery.of(context);
                  return FocusRing(
                    child: MediaQuery(
                      data: media.copyWith(
                        textScaler: TextScaler.linear(
                          media.textScaler.scale(1) * textSize.scale,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                },
                themeMode: mode,
                // The mouse drags the table about, and nothing else: see
                // DragToPanScrollBehavior for why it stops there.
                home: const HomeShell(),
              );
            },
          ),
    );
  }
}
