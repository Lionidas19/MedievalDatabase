import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_controller.dart';
import 'state/view_preferences.dart';
import 'theme.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const PriceExplorerApp());
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
      // Only the three settings that actually change the theme get to rebuild
      // MaterialApp, because rebuilding it rebuilds every screen under it.
      // Watching the whole of ViewPreferences meant that choosing a detail
      // level — which changes some columns and nothing else — tore down and
      // rebuilt the entire app. The screens that care about detail watch it
      // themselves, much further down.
      child: Selector<ViewPreferences,
          (ThemeMode, ThemeVariant, TableDensity)>(
        selector: (_, prefs) =>
            (prefs.themeMode, prefs.variant, prefs.density),
        builder: (context, theme, _) {
          final (mode, variant, density) = theme;
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
            ),
            darkTheme: AppTheme.build(
              variant: variant,
              brightness: Brightness.dark,
              density: density,
            ),
            themeMode: mode,
            // A mouse can drag the table around, not just its scrollbars.
            scrollBehavior: const DragToPanScrollBehavior(),
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
