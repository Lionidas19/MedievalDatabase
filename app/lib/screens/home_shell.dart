import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import '../theme.dart';
import 'onboarding_screen.dart';
import 'advanced/advanced_view.dart';
import 'advanced/edit_entry_dialog.dart';
import 'simple/simple_view.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _announcedRestore = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();

    // Say so once, the first time a session picks up where the last left off.
    // Silently loading someone's edited copy would be indistinguishable from
    // loading the bundled one, which is exactly the confusion to avoid.
    if (app.restoredFromLocal && !_announcedRestore && app.hasData) {
      _announcedRestore = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Picked up your saved copy from this browser, including any '
                'edits from last time.'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Start fresh',
              onPressed: () => _resetToDefault(context, app),
            ),
          ),
        );
      });
    }

    // hasData becomes true almost immediately; this only shows during that
    // brief startup moment, or if the load somehow failed.
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

Future<void> _resetToDefault(BuildContext context, AppController app) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Start again from the bundled database?'),
      content: const Text(
        'This discards the copy saved in this browser, including every edit '
        'made to it. Download a file first if you want to keep any of it.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard and reload')),
      ],
    ),
  );
  if (confirmed != true) return;
  await app.resetToBundledDefault();
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
              child: SelectableText(message,
                  style: TextStyle(color: scheme.onErrorContainer)),
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

/// Shows where the working copy stands with private browser storage.
///
/// Worth being explicit rather than showing a generic "saved": this storage is
/// private to one browser on one machine and cannot be found in a file
/// manager, so anyone treating it as a filing system is heading for a bad day.
class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, text, colour, tooltip) = switch (app.saveState) {
      LocalSaveState.unsupported => (
          Icons.cloud_off_outlined,
          'Not saved',
          scheme.onSurfaceVariant,
          'This browser gives the app no private storage, so edits last only '
              'until you close the tab. Download a file to keep your work.',
        ),
      LocalSaveState.saving => (
          Icons.sync,
          'Saving…',
          scheme.onSurfaceVariant,
          'Writing the working copy to this browser.',
        ),
      LocalSaveState.saved => (
          Icons.check_circle_outline,
          app.lastSavedAt == null ? 'Saved' : 'Saved ${_time(app.lastSavedAt!)}',
          scheme.primary,
          'Saved in this browser only — invisible to your file manager and '
              'gone if you clear site data. Download a file for a copy you can '
              'keep or send.',
        ),
      LocalSaveState.failed => (
          Icons.error_outline,
          'Save failed',
          scheme.error,
          'Could not write to this browser: ${app.saveError ?? 'unknown error'}. '
              'Download a file so your work is not lost.',
        ),
      LocalSaveState.idle => (
          Icons.cloud_done_outlined,
          'No changes',
          scheme.onSurfaceVariant,
          'Nothing edited yet in this session.',
        ),
    };

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colour),
            const SizedBox(width: 6),
            Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colour)),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(t.hour)}:${p2(t.minute)}';
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
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
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
        _SaveIndicator(app: app),
        const SizedBox(width: 4),
        if (!compact)
          OutlinedButton.icon(
            onPressed: app.isLoading ? null : () => _addEntry(context, app),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New entry'),
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: app.isLoading ? null : () => _openFile(context, app),
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Open file'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: app.isLoading ? null : () => _download(context, app),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(app.isDirty ? 'Download changes' : 'Download a copy'),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_MenuAction>(
          tooltip: 'More',
          onSelected: (action) {
            switch (action) {
              case _MenuAction.newEntry:
                _addEntry(context, app);
              case _MenuAction.saveNow:
                app.saveNow();
              case _MenuAction.resetToDefault:
                _resetToDefault(context, app);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _MenuAction.newEntry,
              child: Text('New entry'),
            ),
            PopupMenuItem(
              value: _MenuAction.saveNow,
              child: Text('Save to this browser now'),
            ),
            PopupMenuItem(
              value: _MenuAction.resetToDefault,
              child: Text('Start again from the bundled database'),
            ),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _addEntry(BuildContext context, AppController app) async {
    final entry = app.createEntry();
    if (!context.mounted) return;
    final updated = await showEditEntryDialog(
      context,
      entry: entry,
      repository: app.repository,
      isNew: true,
    );
    if (updated == null) {
      // Cancelled: do not leave an empty row behind.
      app.deleteEntry(entry.entryId);
      return;
    }
    app.applyEdit(updated);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added entry #${updated.legacyEntryNo ?? ''}')),
    );
  }

  Future<void> _openFile(BuildContext context, AppController app) async {
    if (app.isDirty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Replace the working copy?'),
          content: const Text(
            'Opening a different file replaces what you are editing, and what '
            'is saved in this browser. Download your changes first if you want '
            'to keep them.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace and open')),
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
}

enum _MenuAction { newEntry, saveNow, resetToDefault }
