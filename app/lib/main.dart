import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_controller.dart';
import 'theme.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const PriceExplorerApp());
}

class PriceExplorerApp extends StatelessWidget {
  const PriceExplorerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppController(),
      child: MaterialApp(
        title: 'Medieval Price Explorer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}
