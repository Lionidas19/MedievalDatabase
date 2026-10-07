import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';
import '../../theme.dart';

/// The controls the tour can stop at.
///
/// An enum rather than strings so a stop that no longer exists is a compile
/// error rather than a tour that silently points at nothing.
enum TourStop {
  views,
  search,
  pricePer,
  filters,
  figures,
  detailLevels,
  download,
  searchForm,
  searchUnit,
  searchGenerate,
}

/// Where each stop currently is on screen.
///
/// A plain static map rather than an InheritedWidget: the registrations come
/// from four different screens and the only reader is the overlay, which is
/// not in anybody's widget subtree. Keys are removed on dispose so a stop
/// belonging to a view that is no longer built is simply absent, which is
/// what [Tour] checks before trying to point at it.
class TourTargets {
  const TourTargets._();

  static final Map<TourStop, GlobalKey> _keys = {};

  static void register(TourStop stop, GlobalKey key) => _keys[stop] = key;

  static void unregister(TourStop stop, GlobalKey key) {
    if (_keys[stop] == key) _keys.remove(stop);
  }

  /// The build context of a stop that is currently mounted.
  static BuildContext? contextOf(TourStop stop) => _keys[stop]?.currentContext;

  /// The rectangle this stop occupies, or null if it is not on screen.
  ///
  /// Null is the normal case rather than a fault: half these controls only
  /// exist at certain detail levels, and below 640px there is no table at
  /// all. A stop that cannot be found is skipped.
  static Rect? rectOf(TourStop stop) {
    final context = _keys[stop]?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }
}

/// Marks a widget as somewhere the tour can point.
class TourTarget extends StatefulWidget {
  const TourTarget({super.key, required this.stop, required this.child});

  final TourStop stop;
  final Widget child;

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourTargets.register(widget.stop, _key);
  }

  @override
  void dispose() {
    TourTargets.unregister(widget.stop, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// One thing the tour says, and what it says it about.
///
/// [stop] may be null, which means the step has no single control to point
/// at and its card is centred instead. The row-opening step is like that: a
/// table row lives inside a sliver list and cannot be pointed at without
/// churning a key through every row to highlight one of 7,501.
class _Step {
  const _Step(this.stop, this.title, this.body,
      {this.view = ViewMode.advanced});

  final TourStop? stop;

  /// Which screen this step is about.
  ///
  /// The tour switches to it before measuring, and that switch is not
  /// cosmetic: all three screens stay mounted in an `IndexedStack`, so a
  /// control on a screen nobody is looking at still has a perfectly good
  /// rectangle. Measuring without switching would cut a hole over empty
  /// space and point confidently at nothing.
  final ViewMode view;
  final String title;
  final String body;
}

/// A click-through tour over the real screen.
///
/// The researcher asked for "one of those click-through guided tours that
/// says 'this button does x, this button does y'". This is that: an overlay
/// that dims the page, cuts a hole around one control at a time and explains
/// it, rather than a separate slideshow of screenshots that would go stale
/// the moment anything moved.
///
/// **The copy below is placeholder**, written from what each control does so
/// the researcher can edit over something real. See `widgets/info_dot.dart`
/// for the same arrangement with the `(?)` text.
class Tour {
  const Tour._();

  static const _steps = [
    _Step(TourStop.views, 'Two ways in',
        'Data Display is the whole table. Advanced Search answers one '
        'question at a time and draws a chart. You can move between them '
        'whenever you like without losing your place.'),
    _Step(TourStop.search, 'Search',
        'Type a few letters of a place, an item or a category. It searches '
        'all of them at once, so "salt" and "Norfolk" both work here.'),
    _Step(TourStop.pricePer, 'Price per',
        'What unit the prices are worked out in. It starts on "Recorded '
        'unit", which prices each record by whatever the source measured it '
        'by, so there is always an answer. Pick a single unit when you want '
        'to compare one record against another.'),
    _Step(TourStop.filters, 'Filters',
        'Narrow by county, category, date or a range of years. The count '
        'beside the button always tells you how many records are left.'),
    _Step(TourStop.figures, 'The averages',
        'The middle and average price across everything the filters left. '
        'The median leads because one very dear record can drag a mean a '
        'long way.'),
    _Step(TourStop.detailLevels, 'How much to show',
        'Three levels, and they apply everywhere at once. Everything also '
        'unlocks adding and editing records, which is why it is not the '
        'setting you start on.'),
    _Step(null, 'Opening a record',
        'Clicking a row shows you that record in full and changes nothing. '
        'The pencil at the end of the row is what opens it for editing.'),
    _Step(TourStop.download, 'Taking it with you',
        'Saves the whole database, your changes included, as a file. '
        'Everything you do here stays in this browser until you do.'),

    // And over to the other screen, because the whole reason this tour
    // exists is that nobody in testing found it.
    _Step(null, 'The other way to ask', view: ViewMode.simple,
        'That was the table. The second screen answers one question at a '
        'time instead, which is usually what you want if you just need a '
        'price rather than a list.'),
    _Step(TourStop.searchForm, 'Fill in the sentence', view: ViewMode.simple,
        'Read it as a sentence: in this place, between these years, this '
        'item. Leave anything blank and it simply will not narrow by it.'),
    _Step(TourStop.searchUnit, 'What the answer is in', view: ViewMode.simple,
        'The same choice as Price per on the table. It starts on the '
        'measure the source itself used, so there is always an answer.'),
    _Step(TourStop.searchGenerate, 'Get the answer', view: ViewMode.simple,
        'This gives you the average, what it is in modern money, and a '
        'chart of how the price moved across the years you chose. The page '
        'scrolls you to it.'),
  ];

  /// Opens the tour. Does nothing if it is already running.
  static void start(BuildContext context) {
    if (_entry != null) return;
    final overlay = Overlay.of(context);
    final app = context.read<AppController>();
    final startedOn = app.mode;
    // After the frame, so a view switched to in the same callback has been
    // laid out and its targets have registered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entry = OverlayEntry(
builder: (_) => _TourOverlay(
          app: app,
          onClose: () {
            // Put them back where they were, so a tour taken from the Guide
            // does not strand them on a screen they did not choose.
            app.setMode(startedOn);
            _close();
          },
        ),
      );
      overlay.insert(_entry!);
    });
  }

  static OverlayEntry? _entry;

  static void _close() {
    _entry?.remove();
    _entry = null;
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.app, required this.onClose});
  final AppController app;
  final VoidCallback onClose;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _index = 0;

  /// Every step, filtered as we go rather than up front.
  ///
  /// A step cannot be judged before its screen is on show: with all three
  /// mounted in an `IndexedStack`, a target that is not visible still has a
  /// rectangle. So the view is switched first and the step skipped after, in
  /// [_settle].
  List<_Step> get _steps => Tour._steps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
  }

  /// Puts the right screen on show, then moves past a step with nothing to
  /// point at.
  /// Guards the one scroll per step, so settling again after it finishes
  /// does not start the same scroll over.
  bool _scrolled = false;

  void _settle() {
    if (!mounted) return;
    final step = _steps[_index];
    if (widget.app.mode != step.view) {
      widget.app.setMode(step.view);
      // Let it lay out before measuring.
      WidgetsBinding.instance.addPostFrameCallback((_) => _settle());
      return;
    }
    // Bring it into view before cutting a hole over it.
    //
    // The last step points at Generate results, which on a short window sits
    // below the fold: the spotlight was landing half off the bottom of the
    // screen and the card explained a button the reader could not see. A
    // target inside a scroll view is scrolled to first, and the measurement
    // waits for that to finish.
    final target =
        step.stop == null ? null : TourTargets.contextOf(step.stop!);
    if (target != null && !_scrolled) {
      final scrollable = Scrollable.maybeOf(target);
      if (scrollable != null) {
        _scrolled = true;
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          // A little above centre, which leaves room for the card below it.
          alignment: 0.35,
        ).whenComplete(() {
          if (mounted) setState(() {});
        });
        return;
      }
    }

    if (step.stop != null && TourTargets.rectOf(step.stop!) == null) {
      if (_index < _steps.length - 1) {
        _index++;
        _settle();
      } else {
        widget.onClose();
      }
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) {
      // Nothing to point at, which is better handled by leaving than by
      // showing an empty scrim.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onClose());
      return const SizedBox.shrink();
    }

    final step = _steps[_index];
    final rect = step.stop == null ? null : TourTargets.rectOf(step.stop!);
    final size = MediaQuery.of(context).size;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;

    // The hole, with a little room around the control so it does not look
    // clipped.
    final hole = rect?.inflate(6).intersect(Offset.zero & size);

    // The card goes below the hole where there is room, above it otherwise —
    // and beside it when the hole is tall enough that neither fits. The
    // navigation rail is the case that needs the third branch: it runs the
    // full height of the window, so both clamps put the card straight on top
    // of the very destinations the step is describing.
    const cardWidth = 330.0;
    const cardHeight = 186.0;
    final below = hole != null && hole.bottom + cardHeight + 16 < size.height;
    final above = hole != null && hole.top - cardHeight - 16 > 0;
    final beside = hole != null && !below && !above;

    final double top;
    double left;
    if (hole == null) {
      top = size.height / 2 - cardHeight / 2;
      left = size.width / 2 - cardWidth / 2;
    } else if (beside) {
      top = hole.center.dy - cardHeight / 2;
      // To the right of the hole if it will fit there, otherwise the left.
      left = hole.right + 12 + cardWidth + 12 < size.width
          ? hole.right + 12
          : hole.left - cardWidth - 12;
    } else {
      top = below ? hole.bottom + 12 : hole.top - cardHeight - 12;
      left = hole.center.dx - cardWidth / 2;
    }
    left = left.clamp(12.0, size.width - cardWidth - 12);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // The scrim. Tapping it moves on, which is what people try first.
          Positioned.fill(
            child: GestureDetector(
              onTap: _next,
              child: CustomPaint(
                painter: _ScrimPainter(
                    hole: hole, colour: Colors.black.withValues(alpha: 0.55)),
              ),
            ),
          ),
          if (hole != null)
            Positioned(
              left: hole.left,
              top: hole.top,
              width: hole.width,
              height: hole.height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
              ),
            ),
          Positioned(
            left: left,
            top: top.clamp(12.0, size.height - cardHeight - 12),
            width: cardWidth,
            child: Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(Radii.lg),
                boxShadow: const [
                  BoxShadow(blurRadius: 18, color: Color(0x44000000)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_index + 1} of ${_steps.length}',
                      style: theme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(step.title,
                      style: theme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(step.body,
                      style: theme.bodyMedium?.copyWith(height: 1.4)),
                  const SizedBox(height: Spacing.sm),
                  Row(
                    children: [
                      TextButton(
                          onPressed: widget.onClose,
                          child: const Text('Skip')),
                      const Spacer(),
                      if (_index > 0)
                        TextButton(
                            onPressed: _back, child: const Text('Back')),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: _next,
                        child: Text(_index == _steps.length - 1
                            ? 'Done'
                            : 'Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _next() {
    if (_index == _steps.length - 1) {
      widget.onClose();
    } else {
      _index++;
      _scrolled = false;
      _settle();
    }
  }

  void _back() {
    if (_index == 0) return;
    _index--;
    _scrolled = false;
    _settle();
  }
}

/// A dim over everything except one rectangle.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.colour});

  final Rect? hole;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final everything = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(everything, Paint()..color = colour);
      return;
    }
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(8)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, everything, cut),
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole;
}
