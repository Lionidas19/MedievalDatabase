import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_version.dart';
import '../services/install_prompt.dart';
import '../state/app_controller.dart';
import '../state/view_preferences.dart';
import '../theme.dart';
import 'display_settings.dart';
import 'guide_screen.dart';
import 'tour/tour.dart';
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
          appBar: _TopBar(width: constraints.maxWidth),
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
    // Both views stay mounted so switching between them keeps filters,
    // scroll position and a generated result. That has a cost the IndexedStack
    // cannot avoid on its own: a view listening to settings is rebuilt when
    // they change whether or not anybody can see it, and Specifics lookup is
    // expensive to build — its dropdowns hold every locality and output unit
    // the source knows. So each view is told whether it is the one on screen,
    // and only that one subscribes.
    final advanced = mode == ViewMode.advanced;
    return IndexedStack(
      index: switch (mode) {
        ViewMode.advanced => 0,
        ViewMode.simple => 1,
        ViewMode.guide => 2,
      },
      children: [
        AdvancedView(active: advanced),
        SimpleView(active: mode == ViewMode.simple),
        GuideScreen(active: mode == ViewMode.guide),
      ],
    );
  }
}

/// The order both navigations show, and the only place it is stated.
///
/// Index with this, never with `ViewMode.values`. The enum declares
/// `simple` first because `simple` was the first screen written; the rail
/// shows `advanced` first because that is the one people arrive on. Indexing
/// by the enum highlighted Advanced Search whenever Data Display was open,
/// and the other way about.
const _order = [ViewMode.advanced, ViewMode.simple, ViewMode.guide];

class _SideNav extends StatelessWidget {
  const _SideNav({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The rail has no bottom slot of its own — its `trailing` sits directly
    // under the destinations, which would read as a third one — so the version
    // goes below the rail in a Column. The Column carries the rail's own
    // colour so no seam shows where one ends and the other begins.
    return TourTarget(
      stop: TourStop.views,
      child: ColoredBox(
      color: scheme.surfaceContainerLow,
      child: Column(
        children: [
          Expanded(
            child: NavigationRail(
              selectedIndex: _order.indexOf(app.mode),
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => app.setMode(_order[i]),
              destinations: [
                // The unselected icon sits in an outlined pill so it looks
                // like something to press. Material gives the selected one a
                // filled indicator and the other nothing at all, which read
                // as a heading — and nobody pressed it.
                NavigationRailDestination(
                  icon: _RailIcon(icon: Icons.table_chart_outlined),
                  selectedIcon: const Icon(Icons.table_chart),
                  label: const Text('Data Display'),
                ),
                NavigationRailDestination(
                  icon: _RailIcon(icon: Icons.eco_outlined),
                  selectedIcon: const Icon(Icons.eco),
                  label: const Text('Advanced Search'),
                ),
                // The researcher asked for this third button by name, and for
                // the reason it is here: nobody in his testing found the
                // second screen, let alone worked out what it was for.
                NavigationRailDestination(
                  icon: _RailIcon(icon: Icons.help_outline),
                  selectedIcon: const Icon(Icons.help),
                  // His word, not ours. The feedback asks for "a third
                  // button here for 'Tutorial'", and a reader looking for the
                  // thing he told them about should find the name he used.
                  label: const Text('Tutorial'),
                ),
              ],
            ),
          ),
          const _VersionLabel(),
        ],
      ),
    ));
  }
}

/// An unselected rail icon, drawn inside a visible outline.
class _RailIcon extends StatelessWidget {
  const _RailIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(icon, size: 22),
    );
  }
}

/// The build the reader is looking at, in the corner of the navigation rail.
///
/// Worth having in front of them rather than buried in a menu: the database
/// travels between the researcher's browser and the published site, and the
/// first question about anything that looks wrong is which version said it.
class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.sm,
        right: Spacing.sm,
        top: Spacing.sm,
        bottom: Spacing.md,
      ),
      child: FutureBuilder<String>(
        future: AppVersion.version,
        builder: (context, snapshot) => Text(
          // Empty until the bundle answers, which is a frame or two. A
          // placeholder would flicker for longer than the value takes.
          snapshot.data ?? '',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontFeatures: const [tabularFigures],
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _order.indexOf(app.mode),
      onDestinationSelected: (i) => app.setMode(_order[i]),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.table_chart_outlined),
          selectedIcon: Icon(Icons.table_chart),
          label: 'Data Display',
        ),
        NavigationDestination(
          icon: Icon(Icons.eco_outlined),
          selectedIcon: Icon(Icons.eco),
          label: 'Advanced Search',
        ),
        NavigationDestination(
          icon: Icon(Icons.help_outline),
          selectedIcon: Icon(Icons.help),
          label: 'Tutorial',
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
  const _SaveIndicator({required this.app, this.compact = false});
  final AppController app;

  /// Icon only. The words are in the tooltip either way, and 'Saved 14:32' is
  /// 110px a narrow window does not have.
  final bool compact;

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
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colour)),
            ],
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

/// Opens the display settings, and says what the current detail level is.
///
/// The level is the setting most likely to be wrong for a given reader, and
/// the one whose effect is easiest to mistake for missing data — a table
/// showing five columns because it was left on Basics looks exactly like a
/// database that only holds five things. So it is labelled, not just an icon.
class _DisplayButton extends StatelessWidget {
  const _DisplayButton({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<ViewPreferences>();
    if (compact) {
      return IconButton(
        icon: const Icon(Icons.display_settings_outlined),
        tooltip: 'Display settings',
        onPressed: () => showDisplaySettings(context),
      );
    }
    return Tooltip(
      message: 'Detail, theme and row height',
      child: TextButton.icon(
        onPressed: () => showDisplaySettings(context),
        // Not Icons.tune: the Explorer's filter button already wears it,
        // and two identical icons on one screen read as two of the same
        // control.
        icon: const Icon(Icons.display_settings_outlined, size: 18),
        label: Text('Showing: ${prefs.detailLevel.label.toLowerCase()}'),
      ),
    );
  }
}

/// The app bar, which has to give things up as the window narrows.
///
/// It held nine things at fixed sizes and nothing was allowed to shrink, so
/// below about 1300px the title painted straight over the filename beside it,
/// and on a phone the actions overflowed their row. An AppBar hands its title
/// whatever the actions leave over; a `Text` that cannot ellipse takes the
/// space anyway and draws on top of its neighbours.
///
/// So there are three widths, each giving up the least useful thing first:
/// the filename (reassurance, not a control), then the button labels, then
/// Open file, which moves into the overflow menu rather than vanishing.
class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.width});

  /// The window's width, not a flag: the bar needs the number to work out
  /// what it can still afford.
  final double width;

  bool get compact => Breakpoints.isCompact(width);

  /// The filename is the first thing to go. It says which file is open, which
  /// matters once and then never again in a session.
  bool get _showFileName => width >= 1320;

  /// Below this, Open file and Download keep their icons and lose their
  /// words. Both are unmistakable as icons, and both carry a tooltip.
  bool get _labelled => width >= 1160;

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
          // Flexible and ellipsised, which is the backstop for every width
          // the branches below do not anticipate. Without it the name
          // overflows its box and paints over whatever sits beside it.
          Flexible(
            child: Text(
              compact ? 'Price Explorer' : 'Medieval Price Explorer',
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
      actions: [
        if (_showFileName)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              children: [
                Icon(Icons.description_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                // Capped and ellipsised: these names are long, and every file
                // the app hands back carries a timestamp on the end of it.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: Text(
                    app.currentFileName ?? '',
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        _SaveIndicator(app: app, compact: !_labelled),
        const SizedBox(width: 4),
        _DisplayButton(compact: compact),
        const SizedBox(width: 4),
        // New entry used to live here, beside Open file. His note: "New
        // Entry should not be located here. In my opinion it should actually
        // be where you have Basics, More Detail, Everything, but it should
        // ONLY appear after you click on Everything." It now does, in
        // `filter_bar.dart`. The overflow menu below keeps a route to it for
        // short screens, where the detail row is dropped altogether.
        const SizedBox(width: 8),
        // On a phone this moves into the overflow menu. It is the action a
        // reader wants least often and it costs the most width.
        if (!compact)
          _labelled
              ? OutlinedButton.icon(
                  onPressed:
                      app.isLoading ? null : () => _openFile(context, app),
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Open file'),
                )
              : IconButton(
                  tooltip: 'Open file',
                  onPressed:
                      app.isLoading ? null : () => _openFile(context, app),
                  icon: const Icon(Icons.upload_file_outlined),
                ),
        const SizedBox(width: 8),
        // Download keeps its filled treatment at every width. Downloading is
        // the only way work leaves this browser, and the whole storage model
        // rests on a reader finding it.
        TourTarget(
          stop: TourStop.download,
          child: _labelled
              ? FilledButton.icon(
                  onPressed:
                      app.isLoading ? null : () => _download(context, app),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(
                      app.isDirty ? 'Download changes' : 'Download a copy'),
                )
              : IconButton.filled(
                  tooltip:
                      app.isDirty ? 'Download changes' : 'Download a copy',
                  onPressed:
                      app.isLoading ? null : () => _download(context, app),
                  icon: const Icon(Icons.download_outlined),
                ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_MenuAction>(
          tooltip: 'More',
          onSelected: (action) {
            switch (action) {
              case _MenuAction.install:
                promptToInstallApp();
              case _MenuAction.openFile:
                _openFile(context, app);
              case _MenuAction.newEntry:
                _addEntry(context, app);
              case _MenuAction.saveNow:
                app.saveNow();
              case _MenuAction.resetToDefault:
                _resetToDefault(context, app);
            }
          },
          // Built when the menu opens rather than once, because whether the
          // browser is offering to install changes under us: the offer arrives
          // a moment after load, and is gone once it has been taken up.
          itemBuilder: (context) => [
            if (canInstallApp)
              const PopupMenuItem(
                value: _MenuAction.install,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.install_desktop, size: 20),
                  title: Text('Install as an app'),
                  // Says what installing gets them. 'Install' alone reads as
                  // a download, which is the one thing this is not.
                  subtitle: Text('Opens in its own window, and works offline'),
                ),
              ),
            if (compact)
              const PopupMenuItem(
                value: _MenuAction.openFile,
                child: Text('Open a different file'),
              ),
            // Gated with the toolbar button, for the same reason.
            if (context.watch<ViewPreferences>().detailLevel.isEverything)
              const PopupMenuItem(
                value: _MenuAction.newEntry,
                child: Text('New entry'),
              ),
            const PopupMenuItem(
              value: _MenuAction.saveNow,
              child: Text('Save to this browser now'),
            ),
            const PopupMenuItem(
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

enum _MenuAction { install, openFile, newEntry, saveNow, resetToDefault }
