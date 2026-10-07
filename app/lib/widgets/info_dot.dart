import 'package:flutter/material.dart';

/// A small `(i)` beside a control, holding the explanation of what it does.
///
/// The researcher asked for one of these on "basically everything", and wrote
/// the reason into the request: his testers could not tell what "Price per"
/// meant, and there was nowhere to find out. The text is his to write; this is
/// the thing it goes in.
///
/// ## Why it is a button and not just a tooltip
///
/// A plain `Tooltip` is hover-only, and half the audience is on a tablet with
/// no pointer. The same problem was solved for the table's column headings and
/// this is that solution made reusable: the tooltip is held in
/// `TooltipTriggerMode.manual` and opened by tapping a target of its own.
/// Manual mode governs touch only, so a mouse still gets it on hover without a
/// second code path — that is in the framework's own documentation, and it is
/// verified in a Playwright touch context where `matchMedia('(hover: hover)')`
/// is false.
///
/// The tap target is deliberately larger than the glyph. Thirteen pixels of
/// icon is not something a thumb can find.
class InfoDot extends StatefulWidget {
  const InfoDot({
    super.key,
    required this.message,
    required this.label,
    this.size = 15,
  });

  /// What the control does, in plain English.
  final String message;

  /// Names the control for a screen reader: "What does Price per mean?".
  final String label;

  final double size;

  @override
  State<InfoDot> createState() => _InfoDotState();
}

class _InfoDotState extends State<InfoDot> {
  final _tip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      key: _tip,
      message: widget.message,
      triggerMode: TooltipTriggerMode.manual,
      preferBelow: true,
      // Long enough to read a sentence or two on a phone before it goes.
      showDuration: const Duration(seconds: 10),
      // Unbounded, a sentence renders as one line the width of the window.
      constraints: const BoxConstraints(maxWidth: 380),
      child: Semantics(
        button: true,
        label: 'What does ${widget.label} mean?',
        child: InkWell(
          onTap: () => _tip.currentState?.ensureTooltipVisible(),
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.help_outline,
              size: widget.size,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Every explanation the app shows beside a control, in one place.
///
/// Gathered here rather than written inline so the researcher can send prose
/// and have it dropped in without anybody touching a layout. Keys are stable
/// and describe the control; the values are the only part expected to change.
///
/// These are placeholders written from what each control actually does. They
/// are meant to be replaced wholesale by the researcher's own wording.
class Explain {
  const Explain._();

  static const pricePer =
      'What unit the prices are worked out in. "Recorded unit" prices each '
      'entry by whatever measure the source itself used, which always gives '
      'an answer. Choose a single unit instead, such as Kilograms, when you '
      'want to compare one record against another. Entries measured in a kind '
      'of unit that cannot reach your choice are left out rather than '
      'converted into a number that would look real and mean nothing. Units '
      'that cannot price what you are looking at now are crossed out in the '
      'list.';

  static const filters =
      'Narrow the table by county, category, date and year range. The entry '
      'count beside this button always says how many records survive the '
      'filters out of the whole database.';

  static const detailLevel =
      'How much of each record to show. Basics is when, where, what and what '
      'it cost. More detail adds quantities, the time of year and the page. '
      'Everything adds the measures behind each figure and how the '
      'calculation reached its answer. The setting follows you across the '
      'whole app.';

  static const estimates =
      'Fills empty prices with a guess drawn from the trend across '
      'neighbouring years, shown in italics with a tilde so it can never be '
      'mistaken for a record. Off by default, because everything else here is '
      'something the source actually says.';

  static const grouping =
      'Gathers the rows under headings, with the median price for each group '
      'shown on the heading itself.';

  static const reset =
      'Puts the filters, the unit, the sorting and the grouping back to how '
      'the page opens. It does not touch your data.';

  static const search =
      'Searches place names, items, categories and the information column at '
      'once. Type a few letters rather than a whole word.';

  static const figures =
      'The middle, the average and the commonest price across every record '
      'the filters have left, in the unit chosen at Price per. The median is '
      'the one to trust on a broad selection: a single very dear record drags '
      'a mean a long way and leaves a median where it was.';

  static const modernMoney =
      'The recorded price in today\'s pounds, worked out from the value of a '
      'penny in that entry\'s own year and then carried forward for '
      'inflation. It is a guide to scale rather than a valuation: what a '
      'penny bought in 1270 is a question with more than one defensible '
      'answer.';

  static const downloadCopy =
      'Saves the whole database, including anything you have changed, as a '
      'file with today\'s date on it. Nothing you do here reaches anybody '
      'else unless you send them that file.';

  static const openFile =
      'Opens a database file from your computer and works on that instead. '
      'Use it to pick up a copy you downloaded earlier.';

  static const yearRange =
      'The span of years to include. The records run from 1270 to 1291.';

  static const outputUnit =
      'The unit the answer comes back in. "Recorded unit" uses whatever '
      'measure the source used for each entry, so it always has an answer; a '
      'single unit lets you compare entries with each other. Units that '
      'cannot express the records you have selected are struck through.';

  static const averageKind =
      'Which average to report. The median is the middle price and is the '
      'safer choice for a broad selection; the mean is pulled about by a '
      'single extreme record; the mode is the price that occurs most often.';

  static const itemSearch =
      'Type any part of an item and it will search all three levels at once, '
      'so "oats" finds Food / Grain / Oats. The commonest match is offered '
      'first.';

  static const graph =
      'The median price for each year in the range, drawn as a line. Years '
      'with no priced record are left out rather than drawn as zero, and a '
      'year resting on very few records is a thin basis for a trend.';
}
