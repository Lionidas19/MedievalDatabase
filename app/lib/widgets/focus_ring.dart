import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A clear outline round whatever the keyboard is on, drawn over the whole
/// app.
///
/// Material marks a focused button with a tint at about a tenth of the
/// strength of its colour, which on parchment is next to invisible. Tab
/// reached everything in a sensible order and a keyboard reader still could
/// not tell where they were. Restyling every kind of button one by one would
/// leave out whichever kind came next, so instead one ring follows focus,
/// over everything, dialogs and the tour included.
///
/// * **Keyboard only.** Shown while Flutter's highlight mode says the keys
///   are in use, which is what browsers do with `:focus-visible`. A mouse
///   reader never sees it.
/// * **Two colours**, the accent inside a ring of the page colour, so it
///   stands out against light and dark ground alike.
/// * **Not round something that fills half the screen.** The table takes
///   focus as a whole and marks its own current row; an outline round the
///   entire table says nothing and covers its scrollbars.
/// * **Painted, not built.** The position is read at paint time, after
///   layout, so it is never a frame behind a scroll; and only the ring
///   repaints, never the app under it.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, required this.child});
  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  /// Bumped whenever the ring may have moved.
  final _moved = _Pulse();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    FocusManager.instance.removeHighlightModeListener(_onMode);
    _moved.dispose();
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) => _moved.bump();

  /// Focus often lands on something still moving: a dialog growing into
  /// place, a menu sliding open. So the ring follows for a moment after each
  /// change rather than taking one reading at the start of the movement.
  void _onFocus() {
    _moved.bump();
    final until = DateTime.now().add(const Duration(milliseconds: 400));
    void follow(Duration _) {
      if (!mounted || DateTime.now().isAfter(until)) return;
      _moved.bump();
      SchedulerBinding.instance
        ..addPostFrameCallback(follow)
        ..scheduleFrame();
    }

    SchedulerBinding.instance.addPostFrameCallback(follow);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _moved.bump();
        return false;
      },
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RingPainter(
                  repaint: _moved,
                  ring: scheme.primary,
                  halo: scheme.surface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pulse extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required Listenable repaint,
    required this.ring,
    required this.halo,
  }) : super(repaint: repaint);

  final Color ring;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    final focus = FocusManager.instance;
    if (focus.highlightMode != FocusHighlightMode.traditional) return;
    final node = focus.primaryFocus;
    final object = node?.context?.findRenderObject();
    if (node == null || object is! RenderBox || !object.attached) return;
    if (!object.hasSize) return;

    // In this painter's own coordinates, which start at the window's corner
    // because the ring sits over the whole app.
    final rect = MatrixUtils.transformRect(
      object.getTransformTo(null),
      Offset.zero & object.size,
    );
    if (rect.isEmpty || !rect.overlaps(Offset.zero & size)) return;
    if (rect.width * rect.height > size.width * size.height * 0.4) return;

    final shape = RRect.fromRectAndRadius(
      rect.inflate(3),
      const Radius.circular(8),
    );
    canvas
      ..drawRRect(
        shape.inflate(1.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = halo,
      )
      ..drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = ring,
      );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.ring != ring || old.halo != halo;
}
