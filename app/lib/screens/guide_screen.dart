import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/keyboard_help.dart';
import 'tour/tour.dart';
import '../widgets/app_selection.dart';

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
        // Inside the scroll view, where it can see each paragraph; see
        // CopyLayout.
        child: CopyLayout(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What this is', style: theme.headlineSmall),
                  const SizedBox(height: Spacing.sm),
                  // The researcher's own words, from his notes on this page.
                  // The count is the live one: his draft said 7501, which
                  // was already out of date when he wrote it.
                  _P(
                    'This database offers a comprehensive record of what '
                    'things actually cost in England between the years 1270 '
                    'and 1291. It details not only what the item was '
                    '(product, service, fine or tax), but also the place, '
                    'the year, and what measure it was sold by. Sometimes we '
                    'are able to translate these numbers into their modern '
                    'figures, by converting the historic price or weight into '
                    'modern pounds or the metric system, but sometimes, when '
                    'the historic measure is unknown, a best guess or no '
                    'guess is all that is available.',
                  ),
                  _P(
                    'At present there are ${app.entries.length} records. To '
                    'use the database you make use of one of the two search '
                    'options, which you can customise to display the results '
                    'in the original, modern or other historic measurements.',
                  ),

                  const SizedBox(height: Spacing.lg),
                  _Card(
                    scheme: scheme,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Take the tour',
                          style: theme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _P(
                          'A walk through the main screen, one control at a '
                          'time. About a minute, and you can stop at any '
                          'point.',
                        ),
                        const SizedBox(height: Spacing.sm),
                        FilledButton.icon(
                          // No setMode here: the tour moves between screens
                          // itself now, and it puts the reader back where they
                          // started when it ends. Switching first made the
                          // Guide the screen it could never return to.
                          onPressed: () => Tour.start(
                            context,
                            currentMode: () => app.mode,
                            setMode: app.setMode,
                          ),
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
                    body:
                        'Every record, as a table you can filter, sort and '
                        'group. Use it to browse, to compare, or to find a '
                        'particular entry. Clicking a row shows you that record '
                        'in full; it does not change anything.',
                  ),
                  _Entry(
                    icon: Icons.eco_outlined,
                    title: 'Advanced Search',
                    body:
                        'One plain answer instead of a table. Say what, '
                        'where and when, and it gives you the average price, '
                        'what that is in today\'s money, and a chart of how it '
                        'moved over the years you chose.',
                  ),

                  const SizedBox(height: Spacing.lg),
                  Text('How much detail you see', style: theme.titleLarge),
                  const SizedBox(height: Spacing.sm),
                  _P(
                    'The Basics, More detail and Everything buttons change how '
                    'much of each record is shown, everywhere at once.',
                  ),
                  _Bullet(
                    'Basics: when, where, what and how much, and what it '
                    'cost then and in today\'s money.',
                  ),
                  _Bullet(
                    'More detail: adds the entry number, the time of year '
                    'and the quantity in metric.',
                  ),
                  _Bullet(
                    'Everything: adds the measures behind each figure, '
                    'how the sum was reached, the page it was read off, and '
                    'the ability to add records.',
                  ),

                  const SizedBox(height: Spacing.lg),
                  Text('Things worth knowing', style: theme.titleLarge),
                  const SizedBox(height: Spacing.sm),
                  // His wording, except one clause: he wrote that the
                  // date of Michaelmas "could occur on a different day each
                  // year". Not in these years: 29 September is 6 October by
                  // modern reckoning in every year from 1270 to 1291, which
                  // calendar_test.dart checks year by year. It moves to 7
                  // October only in 1300.
                  _Bullet(
                    'Each "year" begins on Michaelmas of the prior year, which '
                    'typically marked the day the agricultural year ended, '
                    'rents were paid, and a feast was held to celebrate the '
                    'end of the year. It is traditionally kept on 29 '
                    'September, but the medieval calendar runs behind the '
                    'modern one, so our first records for the year "1270" '
                    'actually begin on 6 October 1269 and end on 6 October '
                    '1270, by modern reckoning. These calculations are based '
                    'on the work of Stephen Morse '
                    '(https://stevemorse.org/jcal/julian.html).',
                  ),
                  _Bullet(
                    'A dash means the source does not say. The app will not '
                    'invent a figure to fill a gap in the records.',
                  ),
                  _Bullet(
                    'Prices are based on whatever the original source '
                    'measured them by. If it was measured by the quarter, it '
                    'is shown by the quarter. You can change this at "Price '
                    'per" to get more precise historic or modern estimates.',
                  ),
                  _Bullet(
                    'Today\'s money is a guide to scale, not a valuation. What '
                    'a penny bought in 1270 is a question with more than one '
                    'defensible answer. Our estimate is based on the figures '
                    'of the UK\'s National Archives '
                    '(https://www.nationalarchives.gov.uk/currency-converter/).',
                  ),
                  _Bullet(
                    'A note mark beside an item means the record says '
                    'more: the form the thing took, whether pay came partly '
                    'as food, or a gloss. Hover over it or tap it.',
                  ),
                  _Bullet(
                    'Search takes an entry number too, such as 3482, or '
                    'a run of them, such as 3480-3490.',
                  ),
                  _Bullet(
                    'If the text is hard going, the Display button at the top '
                    'has reading options: a typeface made for low vision, one '
                    'many readers with dyslexia prefer, larger text, and more '
                    'space between letters and lines.',
                  ),
                  _Bullet(
                    'Everything can be done from the keyboard. See Using '
                    'the keyboard, below.',
                  ),
                  // His draft ends "The easiest way to contact us is (insert
                  // email/discord here)". Left out until there is an address
                  // to put in it: a placeholder on the live site reads as
                  // an unfinished one.
                  _Bullet(
                    'You can make changes to this database: to individual '
                    'entries, or by creating entirely new entries from your '
                    'own data. Nothing you edit reaches anybody else unless '
                    'you download the file and send it to the creators, to '
                    'be added to the database.',
                  ),

                  // Laid out as keys and what they do rather than as prose: a
                  // reader comes back to this to look one key up, not to read
                  // it through again.
                  const SizedBox(height: Spacing.lg),
                  Text('Using the keyboard', style: theme.titleLarge),
                  const SizedBox(height: Spacing.sm),
                  _P(
                    'You never need the mouse. Tab moves forward through the '
                    'controls on a screen and Shift+Tab moves back; the one '
                    'you are on is outlined. Press ? at any time to bring '
                    'this list up over whatever you are doing.',
                  ),
                  const SizedBox(height: Spacing.sm),
                  const KeyboardShortcuts(),

                  const SizedBox(height: Spacing.lg),
                  Text('Look for the question marks', style: theme.titleLarge),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _P(
                          'Wherever you see one of these, it offers notes '
                          'explaining the control beside it. Tap or hover.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.xl),
                ],
              ),
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
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
    ),
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
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
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
                Text(
                  title,
                  style: theme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: theme.bodyMedium?.copyWith(height: 1.45)),
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
