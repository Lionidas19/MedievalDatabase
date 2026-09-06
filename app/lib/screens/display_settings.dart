import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/view_preferences.dart';
import '../theme.dart';

/// Everything about how the app looks and how much it shows, in one place.
///
/// These settings are deliberately not scattered across the screens they
/// affect. A reader who wants "everything" wants it in the table and in the
/// editor both, and someone setting the app up for a projector should not have
/// to find the contrast switch on the screen they happen to be on.
Future<void> showDisplaySettings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _DisplaySettingsDialog(),
  );
}

class _DisplaySettingsDialog extends StatelessWidget {
  const _DisplaySettingsDialog();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<ViewPreferences>();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.xl, Spacing.lg, Spacing.md, Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Display',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _heading(context, 'How much detail'),
                    _caption(
                      context,
                      'Applies everywhere — the table, the cards and the '
                      'entry editor all follow this.',
                    ),
                    for (final level in DetailLevel.values)
                      RadioListTile<DetailLevel>(
                        contentPadding: EdgeInsets.zero,
                        value: level,
                        // ignore: deprecated_member_use
                        groupValue: prefs.detailLevel,
                        // ignore: deprecated_member_use
                        onChanged: (v) =>
                            prefs.detailLevel = v ?? prefs.detailLevel,
                        title: Text(level.label),
                        subtitle: Text(level.description),
                      ),
                    const SizedBox(height: Spacing.lg),

                    _heading(context, 'Light or dark'),
                    const SizedBox(height: Spacing.sm),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                            value: ThemeMode.system, label: Text('System')),
                        ButtonSegment(
                            value: ThemeMode.light, label: Text('Light')),
                        ButtonSegment(
                            value: ThemeMode.dark, label: Text('Dark')),
                      ],
                      selected: {prefs.themeMode},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => prefs.themeMode = s.first,
                    ),
                    const SizedBox(height: Spacing.lg),

                    _heading(context, 'Palette'),
                    for (final variant in ThemeVariant.values)
                      RadioListTile<ThemeVariant>(
                        contentPadding: EdgeInsets.zero,
                        value: variant,
                        // ignore: deprecated_member_use
                        groupValue: prefs.variant,
                        // ignore: deprecated_member_use
                        onChanged: (v) => prefs.variant = v ?? prefs.variant,
                        title: Text(variant.label),
                        subtitle: Text(variant.description),
                      ),
                    const SizedBox(height: Spacing.lg),

                    _heading(context, 'Row height'),
                    const SizedBox(height: Spacing.sm),
                    SegmentedButton<TableDensity>(
                      segments: [
                        for (final d in TableDensity.values)
                          ButtonSegment(value: d, label: Text(d.label)),
                      ],
                      selected: {prefs.density},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => prefs.density = s.first,
                    ),
                    const SizedBox(height: Spacing.lg),

                    _heading(context, 'Dates'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: prefs.showGregorian,
                      onChanged: (v) => prefs.showGregorian = v,
                      title: const Text('Show the modern date alongside'),
                      subtitle: const Text(
                        'The accounts are Julian, so a full date in them is '
                        'seven days behind modern reckoning. Only 108 of the '
                        '7,800 entries carry a day of the month; a bare year '
                        'reads the same in either calendar.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);

  Widget _caption(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
}
