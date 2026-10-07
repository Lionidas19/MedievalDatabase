import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import '../theme.dart';
import 'tour/tour.dart';

/// "This is what this database does, this is how you can use it."
///
/// The researcher's own words for what he wanted, and the reason he wanted
/// it: observed testers worked out roughly what the app was, then spent a
/// long time failing to find the search, never touched the second screen at
/// all, and edited records they meant only to read.
///
/// He also asked for a click-through tour, and both live here: this page is
/// what you read, the tour is what you watch. The page comes first because a
/// tour that points at controls is no use to somebody who does not yet know
/// what the thing is for.
///
/// **Every word below is placeholder.** The researcher said he would write
/// this copy. It is written out properly rather than left as lorem so he can
/// see the shape and edit over it, and so the app is not embarrassing in the
/// meantime. Replace freely; nothing here is load-bearing.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, required this.active});

  /// Only the visible view subscribes; see `_ModeBody`.
  final bool active;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  /// Its own, and handed to both the Scrollbar and the scroll view.
  ///
  /// `theme.dart` turns `thumbVisibility` on for every scrollbar in the app,
  /// and a scrollbar told to stay visible asserts that it has a position to
  /// describe. With no controller, both this bar and the view below it fall
  /// back to the PrimaryScrollController, which on web and desktop a
  /// SingleChildScrollView does not adopt. The bar then found a controller
  /// with nothing attached and threw on every frame it painted:
  /// "The Scrollbar's ScrollController has no ScrollPosition attached."
  /// Release builds strip the assertion, which is why this only ever appeared
  /// under `flutter run`.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final app = widget.active
        ? context.watch<AppController>()
        : context.read<AppController>();

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(Spacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What this is', style: theme.headlineSmall),
                const SizedBox(height: Spacing.sm),
                _P('A record of what things actually cost in England between '
                    '1270 and 1291, taken from Thorold Rogers\' History of '
                    'Agriculture and Prices in England. Every figure here is '
                    'something a medieval clerk wrote down in an account '
                    'roll: a price, a place, a year, and the measure it was '
                    'sold by.'),
                _P('There are ${app.entries.length} records. The app works '
                    'out what each one comes to in whatever unit you ask for, '
                    'and what it would be in today\'s money.'),

                const SizedBox(height: Spacing.lg),
                _Card(
                  scheme: scheme,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Take the tour',
                          style: theme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      _P('A walk through the main screen, one control at a '
                          'time. About a minute, and you can stop at any '
                          'point.'),
                      const SizedBox(height: Spacing.sm),
                      FilledButton.icon(
                        // No setMode here: the tour moves between screens
                        // itself now, and it puts the reader back where they
                        // started when it ends. Switching first made the
                        // Guide the screen it could never return to.
                        onPressed: () => Tour.start(context),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('Start the tour'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: Spacing.lg),
                Text('The two screens', style: theme.titleLarge),
                const SizedBox(height: Spacing.sm),
                _Entry(
                  icon: Icons.table_chart_outlined,
                  title: 'Data Display',
                  body: 'Every record, as a table you can filter, sort and '
                      'group. Use it to browse, to compare, or to find a '
                      'particular entry. Clicking a row shows you that record '
                      'in full; it does not change anything.',
                ),
                _Entry(
                  icon: Icons.eco_outlined,
                  title: 'Advanced Search',
                  body: 'One plain answer instead of a table. Say what, '
                      'where and when, and it gives you the average price, '
                      'what that is in today\'s money, and a chart of how it '
                      'moved over the years you chose.',
                ),

                const SizedBox(height: Spacing.lg),
                Text('How much detail you see', style: theme.titleLarge),
                const SizedBox(height: Spacing.sm),
                _P('The Basics, More detail and Everything buttons change how '
                    'much of each record is shown, everywhere at once.'),
                _Bullet('Basics: when, where, what, and what it cost.'),
                _Bullet('More detail: adds the quantities, the time of year '
                    'and the page it was read off.'),
                _Bullet('Everything: adds the measures behind each figure, '
                    'how the sum was reached, and the ability to add records.'),

                const SizedBox(height: Spacing.lg),
                Text('Things worth knowing', style: theme.titleLarge),
                const SizedBox(height: Spacing.sm),
                _Bullet('A dash means the source does not say, not that the '
                    'answer is nothing. The app will not invent a figure to '
                    'fill a gap.'),
                _Bullet('Prices are per whatever the source measured the '
                    'thing by, until you choose a single unit at Price per. '
                    'That is why a median across everything should be read '
                    'with care.'),
                _Bullet('Today\'s money is a guide to scale, not a valuation. '
                    'What a penny bought in 1270 is a question with more than '
                    'one defensible answer.'),
                _Bullet('Years are given as the records give them. The '
                    'accounting year ran from Michaelmas, not from January.'),
                _Bullet('Anything you change stays in your own browser. '
                    'Nothing you do here reaches anybody else unless you '
                    'download the file and send it.'),

                const SizedBox(height: Spacing.lg),
                Text('Look for the question marks', style: theme.titleLarge),
                const SizedBox(height: Spacing.sm),
                Row(
                  children: [
                    Icon(Icons.help_outline,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _P('Wherever you see one of these, it explains '
                          'the control beside it. Tap or hover.'),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _P extends StatelessWidget {
  const _P(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                  color: scheme.primary, shape: BoxShape.circle),
            ),
          ),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style:
                        theme.bodyMedium?.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.scheme});
  final Widget child;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
        ),
        child: child,
      );
}
