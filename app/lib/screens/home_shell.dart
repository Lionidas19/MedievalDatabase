import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import '../theme.dart';
import 'onboarding_screen.dart';
import 'advanced/advanced_view.dart';
import 'simple/simple_view.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();

    // hasData becomes true almost immediately (the bundled sample database
    // loads with no folder picker needed); this only shows during that
    // brief startup moment, or if even the bundled load somehow failed.
    if (!app.hasData) {
      return const Scaffold(body: OnboardingScreen());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = Breakpoints.isCompact(constraints.maxWidth);
        return Scaffold(
          appBar: _TopBar(compact: compact),
          body: Column(
            children: [
              if (app.error != null) _ErrorBanner(message: app.error!),
              Expanded(
                child: compact
                    ? const _ModeBody()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SideNav(app: app),
                          const VerticalDivider(width: 1),
                          const Expanded(child: _ModeBody()),
                        ],
                      ),
              ),
            ],
          ),
          bottomNavigationBar: compact ? _BottomNav(app: app) : null,
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(message, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeBody extends StatelessWidget {
  const _ModeBody();

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<AppController>().mode;
    return IndexedStack(
      index: mode == ViewMode.advanced ? 0 : 1,
      children: const [AdvancedView(), SimpleView()],
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: app.mode == ViewMode.advanced ? 0 : 1,
      labelType: NavigationRailLabelType.all,
      onDestinationSelected: (i) =>
          app.setMode(i == 0 ? ViewMode.advanced : ViewMode.simple),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.table_chart_outlined),
          selectedIcon: Icon(Icons.table_chart),
          label: Text('Explorer'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.eco_outlined),
          selectedIcon: Icon(Icons.eco),
          label: Text('Quick lookup'),
        ),
      ],
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: app.mode == ViewMode.advanced ? 0 : 1,
      onDestinationSelected: (i) =>
          app.setMode(i == 0 ? ViewMode.advanced : ViewMode.simple),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.table_chart_outlined),
          selectedIcon: Icon(Icons.table_chart),
          label: 'Explorer',
        ),
        NavigationDestination(
          icon: Icon(Icons.eco_outlined),
          selectedIcon: Icon(Icons.eco),
          label: 'Quick lookup',
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.compact});
  final bool compact;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;

    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.castle_outlined, size: 22),
          const SizedBox(width: 10),
          Text(compact ? 'Price Explorer' : 'Medieval Price Explorer'),
        ],
      ),
      actions: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  app.currentFileName ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        if (app.isDirty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Chip(
              avatar: const Icon(Icons.circle, size: 10, color: Colors.orange),
              label: const Text('Unsaved changes'),
              visualDensity: VisualDensity.compact,
            ),
          ),
        OutlinedButton.icon(
          onPressed: app.isLoading ? null : () => _openFile(context, app),
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Open file'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: (app.isDirty && !app.isLoading) ? () => _download(context, app) : null,
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Download changes'),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_MenuAction>(
          tooltip: 'More',
          onSelected: (action) {
            switch (action) {
              case _MenuAction.resetToDefault:
                _resetToDefault(context, app);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _MenuAction.resetToDefault,
              child: Text('Reload bundled default'),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _openFile(BuildContext context, AppController app) async {
    if (app.isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Opening a different file will replace what you\'re currently editing. '
            'Download your changes first if you want to keep them.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard and open')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    final opened = await app.openFileFromDevice();
    if (!context.mounted || !opened) return;
    final err = app.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Opened ${app.currentFileName}'),
        backgroundColor: err != null ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _download(BuildContext context, AppController app) async {
    final name = app.downloadCurrentFile();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloaded as $name')),
    );
  }

  Future<void> _resetToDefault(BuildContext context, AppController app) async {
    if (app.isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('This reloads the database bundled with the app, discarding your edits.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard and reload')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await app.resetToBundledDefault();
  }
}

enum _MenuAction { resetToDefault }
