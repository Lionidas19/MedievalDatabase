import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/view_mode.dart';
import '../../theme.dart';

/// The controls the tour can stop at.
///
/// An enum rather than strings so a stop that no longer exists is a compile
/// error rather than a tour that silently points at nothing.
enum TourStop {
  views,
  otherScreen,
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
  const _Step(
    this.stop,
    this.title,
    this.body, {
    this.view = ViewMode.advanced,
    this.arrow = false,
  });

  final TourStop? stop;

  /// Draws an arrow from the card to the control, and stands the card off
  /// far enough for the arrow to be seen. For the step where the reader has
  /// to go and press the thing themselves: a ring round a small icon at the
  /// edge of the screen was easy to look straight past.
  final bool arrow;

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
    _Step(
      TourStop.views,
      'Two ways in',
      'Data Display is the whole table. Advanced Search answers one '
          'question at a time and draws a chart. You can move between them '
          'whenever you like without losing your place.',
    ),
    _Step(
      TourStop.search,
      'Search',
      'Type a few letters of a place, an item or a category. It searches '
          'all of them at once, so "salt" and "Norfolk" both work here.',
    ),
    _Step(
      TourStop.pricePer,
      'Price per',
      'What unit the prices are worked out in. It starts on the measure '
          'each record used, so there is always an answer. Pick "Modern (# or '
          'Metric Kg)" or a single unit when you want to compare one record '
          'against another.',
    ),
    _Step(
      TourStop.filters,
      'Filters',
      'Narrow by county, category, date or a range of years. The count '
          'beside the button always tells you how many records are left.',
    ),
    _Step(
      TourStop.figures,
      'The averages',
      'The middle and average price across everything the filters left. '
          'The median leads because one very dear record can drag a mean a '
          'long way.',
    ),
    _Step(
      TourStop.detailLevels,
      'How much to show',
      'Three levels, and they apply everywhere at once. Everything also '
          'unlocks adding and editing records, which is why it is not the '
          'setting you start on.',
    ),
    _Step(
      null,
      'Opening a record',
      'Clicking a row shows you that record in full and changes nothing. '
          'The pencil at the end of the row is what opens it for editing.',
    ),
    _Step(
      TourStop.download,
      'Taking it with you',
      'Saves the whole database, your changes included, as a file. '
          'Everything you do here stays in this browser until you do.',
    ),

    // And over to the other screen, because the whole reason this tour
    // exists is that nobody in testing found it. The researcher asked for
    // the button itself to be pointed at first, with an arrow, before the
    // tour goes there: showing the screen alone never taught anybody where
    // it was.
    _Step(
      TourStop.otherScreen,
      'The other screen',
      arrow: true,
      'Advanced Search is here. Click it whenever you want the second '
          'screen, which answers one question at a time.',
    ),
    _Step(
      null,
      'The other way to ask',
      view: ViewMode.simple,
      'That was the Data Display. This is Advanced Search, which answers '
          'one question at a time instead: usually what you want if you just '
          'need a price rather than a list.',
    ),
    _Step(
      TourStop.searchForm,
      'Fill in the sentence',
      view: ViewMode.simple,
      'Read it as a sentence: in this place, between these years, this '
          'item. Leave anything blank and it simply will not narrow by it.',
    ),
    _Step(
      TourStop.searchUnit,
      'What the answer is in',
      view: ViewMode.simple,
      'The same choice as Price per on the table. It starts on the '
          'measure the source itself used, so there is always an answer.',
    ),
    _Step(
      TourStop.searchGenerate,
      'Get the answer',
      view: ViewMode.simple,
      'This gives you the average, what it is in modern money, and a '
          'chart of how the price moved across the years you chose. The page '
          'scrolls you to it.',
    ),
    _Step(
      null,
      'Without a mouse',
      view: ViewMode.simple,
      'Everything here works from the keyboard. Alt and 1, 2 or 3 move '
          'between the three screens, and ? shows every key at any time. The '
          'whole list is on the Tutorial page.',
    ),
    _Step(
      null,
      'Thank you',
      view: ViewMode.simple,
      'Thank you for completing the tutorial! You can take it again at any '
          'time from the Tutorial page.',
    ),
  ];

  /// Opens the tour. Does nothing if it is already running.
  /// [currentMode] and [setMode] are passed in rather than read from a
  /// provider, so this file never has to import `AppController`. See
  /// `state/view_mode.dart` for why that matters.
  static void start(
    BuildContext context, {
    required ViewMode Function() currentMode,
    required ValueChanged<ViewMode> setMode,
  }) {
    if (_entry != null) return;
    final overlay = Overlay.of(context);
    final startedOn = currentMode();
    // After the frame, so a view switched to in the same callback has been
    // laid out and its targets have registered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entry = OverlayEntry(
        builder: (_) => _TourOverlay(
          currentMode: currentMode,
          setMode: setMode,
          onClose: () {
            // Put them back where they were, so a tour taken from the Guide
            // does not strand them on a screen they did not choose.
            setMode(startedOn);
            _close();
          },
        ),
      );
      overlay.insert(_entry!);
    });
  }

  static OverlayEntry? _entry;

  /// So the app-wide keys can stand aside while the tour is moving the
  /// reader between screens itself.
  static bool get isRunning => _entry != null;

  static void _close() {
    _entry?.remove();
    _entry = null;
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({
    required this.currentMode,
    required this.setMode,
    required this.onClose,
  });

  final ViewMode Function() currentMode;
  final ValueChanged<ViewMode> setMode;
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

  /// Next takes focus when the tour opens, asked for outright rather than
  /// by `autofocus`, which stands aside whenever something on the page
  /// already has focus. Started from the table, the table kept the keys.
  final _nextButton = FocusNode(debugLabel: 'tour next');

  /// The tour's own scope, so it can tell when focus has left it.
  final _scope = FocusScopeNode(debugLabel: 'tour');

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_keepFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nextButton.requestFocus();
      _settle();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_keepFocus);
    _nextButton.dispose();
    _scope.dispose();
    super.dispose();
  }

  /// Holds the keyboard while the tour is open, the way a dialog does.
  ///
  /// The tour is an overlay, not a route, so nothing traps focus inside it
  /// for free, and the page under the scrim can take it back. The text
  /// selection does exactly that: the click on "Start the tour" lands inside
  /// a selectable page, which claims focus as the click finishes, after the
  /// tour had given it to Next. The arrows then went to the page and the
  /// tour sat on its first step.
  void _keepFocus() {
    if (!mounted || _scope.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _nextButton.requestFocus();
    });
  }

  /// Puts the right screen on show, then moves past a step with nothing to
  /// point at.
  /// Guards the one scroll per step, so settling again after it finishes
  /// does not start the same scroll over.
  bool _scrolled = false;

  /// Which way the reader is going, so a step with nothing to point at is
  /// skipped in that direction. Always skipping forwards meant Back over
  /// such a step bounced straight back to where it started, and the steps
  /// before it could not be reached again.
  int _direction = 1;

  void _settle() {
    if (!mounted) return;
    final step = _steps[_index];
    if (widget.currentMode() != step.view) {
      widget.setMode(step.view);
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
    final target = step.stop == null ? null : TourTargets.contextOf(step.stop!);
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
      final next = _index + _direction;
      if (next >= 0 && next < _steps.length) {
        _index = next;
        _settle();
      } else if (_direction < 0) {
        // Nothing earlier can be shown, so carry on forwards from here.
        _direction = 1;
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
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
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
    // With an arrow, the card stands off far enough for it to be seen.
    final gap = step.arrow ? 64.0 : 12.0;
    final below =
        hole != null && hole.bottom + gap + cardHeight + 4 < size.height;
    final above = hole != null && hole.top - gap - cardHeight - 4 > 0;
    final beside = hole != null && !below && !above;

    final double top;
    double left;
    if (hole == null) {
      top = size.height / 2 - cardHeight / 2;
      left = size.width / 2 - cardWidth / 2;
    } else if (beside) {
      top = hole.center.dy - cardHeight / 2;
      // To the right of the hole if it will fit there, otherwise the left.
      left = hole.right + gap + cardWidth + 12 < size.width
          ? hole.right + gap
          : hole.left - cardWidth - gap;
    } else {
      top = below ? hole.bottom + gap : hole.top - cardHeight - gap;
      left = hole.center.dx - cardWidth / 2;
    }
    left = left.clamp(12.0, size.width - cardWidth - 12);
    final cardTop = top.clamp(12.0, size.height - cardHeight - 12);

    // From the card's edge to the hole's, straight across the gap between.
    final (Offset, Offset)? arrow = !step.arrow || hole == null
        ? null
        : beside
        ? (
            Offset(left > hole.right ? left : left + cardWidth, hole.center.dy),
            Offset(
              left > hole.right ? hole.right + 4 : hole.left - 4,
              hole.center.dy,
            ),
          )
        : below
        ? (
            Offset(hole.center.dx, cardTop),
            Offset(hole.center.dx, hole.bottom + 4),
          )
        : (
            Offset(hole.center.dx, cardTop + cardHeight),
            Offset(hole.center.dx, hole.top - 4),
          );

    // The keys every guided tour on the web answers to: the arrows to move,
    // Enter for the button that is waiting, Escape to leave. Enter needs
    // nothing here, because Next starts with focus. Its own focus scope, so
    // Tab stays among Skip, Back and Next instead of wandering into the page
    // underneath the scrim.
    return FocusScope(
      node: _scope,
      autofocus: true,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape) {
            widget.onClose();
          } else if (key == LogicalKeyboardKey.arrowRight) {
            _next();
          } else if (key == LogicalKeyboardKey.arrowLeft) {
            _back();
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // The scrim. Tapping it moves on, which is what people try first.
              Positioned.fill(
                child: GestureDetector(
                  onTap: _next,
                  child: CustomPaint(
                    painter: _ScrimPainter(
                      hole: hole,
                      colour: Colors.black.withValues(alpha: 0.55),
                    ),
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
              if (arrow != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ArrowPainter(
                        from: arrow.$1,
                        to: arrow.$2,
                        colour: scheme.primaryContainer,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: left,
                top: cardTop,
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
                      Text(
                        '${_index + 1} of ${_steps.length}',
                        style: theme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.title,
                        style: theme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.body,
                        style: theme.bodyMedium?.copyWith(height: 1.4),
                      ),
                      const SizedBox(height: Spacing.sm),
                      Row(
                        children: [
                          TextButton(
                            onPressed: widget.onClose,
                            child: const Text('Skip'),
                          ),
                          const Spacer(),
                          if (_index > 0)
                            TextButton(
                              onPressed: _back,
                              child: const Text('Back'),
                            ),
                          const SizedBox(width: 4),
                          FilledButton(
                            focusNode: _nextButton,
                            onPressed: _next,
                            child: Text(
                              _index == _steps.length - 1 ? 'Done' : 'Next',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _next() {
    if (_index == _steps.length - 1) {
      widget.onClose();
    } else {
      _index++;
      _direction = 1;
      _scrolled = false;
      _settle();
    }
  }

  void _back() {
    if (_index == 0) return;
    _index--;
    _direction = -1;
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

/// A thick arrow across the gap from the tour's card to what it points at.
///
/// In the accent's light tint rather than the accent itself, because it is
/// drawn over the dark scrim, where the accent all but disappears.
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({
    required this.from,
    required this.to,
    required this.colour,
  });

  final Offset from;
  final Offset to;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final line = to - from;
    if (line.distance < 12) return;
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final direction = line / line.distance;
    final normal = Offset(-direction.dy, direction.dx);
    const head = 14.0;
    canvas
      ..drawLine(from, to - direction * 4, paint)
      ..drawPath(
        Path()
          ..moveTo(to.dx, to.dy)
          ..lineTo(
            (to - direction * head + normal * head * 0.7).dx,
            (to - direction * head + normal * head * 0.7).dy,
          )
          ..lineTo(
            (to - direction * head - normal * head * 0.7).dx,
            (to - direction * head - normal * head * 0.7).dy,
          )
          ..close(),
        Paint()..color = colour,
      );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.from != from || old.to != to || old.colour != colour;
}
