import 'package:flutter/material.dart';

import '../theme.dart';

/// One year's worth of prices, reduced to the figure worth plotting.
class YearPoint {
  const YearPoint({
    required this.year,
    required this.median,
    required this.count,
  });

  final int year;
  final double median;

  /// How many priced records the median rests on. A year standing on two
  /// records is not evidence of a trend, and the chart says so by drawing its
  /// mark smaller rather than by hiding it.
  final int count;
}

/// Median price per year, drawn as a line.
///
/// The researcher asked for "a year range and it could display the
/// information over time as a line graph or something". Three decisions in
/// how it is drawn, each one load-bearing:
///
/// - **The median, not the mean.** A single very dear record drags a mean a
///   long way; across a broad selection the mean here runs to 253 against a
///   median of 0.19. Plotting the mean would draw a line about one record.
/// - **A year with no priced record is a gap, not a zero.** The line breaks
///   rather than diving to the axis and back, because a missing price is
///   silence and a zero is a claim.
/// - **No package.** This is a CustomPainter over plain numbers. The app must
///   run with no network and ships no third-party chart code; drawing a
///   polyline is not worth a dependency.
class PriceTrendChart extends StatelessWidget {
  const PriceTrendChart({
    super.key,
    required this.points,
    required this.unitName,
    this.height = 190,
  });

  final List<YearPoint> points;
  final String unitName;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;

    if (points.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Text(
          points.isEmpty
              ? 'No priced records in this range to chart.'
              : 'Only one year here has a priced record, so there is no '
                  'trend to draw.',
          style: theme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Median pence per $unitName, by year',
          style: theme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: Spacing.sm),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              points: points,
              line: scheme.primary,
              grid: scheme.outlineVariant,
              text: scheme.onSurfaceVariant,
              fill: scheme.primary.withValues(alpha: 0.10),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Each point is the middle price of that year. A smaller point rests '
          'on fewer records; years with no priced record are left as gaps.',
          style: theme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.line,
    required this.grid,
    required this.text,
    required this.fill,
  });

  final List<YearPoint> points;
  final Color line;
  final Color grid;
  final Color text;
  final Color fill;

  // Room for the value labels on the left and the years underneath.
  static const _left = 52.0;
  static const _bottom = 22.0;
  static const _top = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_left, _top, size.width, size.height - _bottom);
    if (plot.width <= 0 || plot.height <= 0) return;

    final years = points.map((p) => p.year).toList();
    final minYear = years.first;
    final maxYear = years.last;
    final values = points.map((p) => p.median).toList();
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    // A perfectly flat series would divide by zero and draw on the edge.
    if (hi - lo < 1e-12) {
      hi = hi == 0 ? 1 : hi * 1.1;
      lo = lo == 0 ? 0 : lo * 0.9;
    }

    double x(int year) => maxYear == minYear
        ? plot.center.dx
        : plot.left + (year - minYear) / (maxYear - minYear) * plot.width;
    double y(double v) =>
        plot.bottom - (v - lo) / (hi - lo) * plot.height;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: text, fontSize: 10);

    // Three gridlines: the bottom, the middle and the top of the range. More
    // than that on 190 pixels is hatching, not a scale.
    for (final t in [0.0, 0.5, 1.0]) {
      final value = lo + (hi - lo) * t;
      final yy = y(value);
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      _label(canvas, _format(value), Offset(plot.left - 6, yy),
          labelStyle, alignRight: true);
    }

    // The first and last year, which is what a reader needs to orient.
    _label(canvas, '$minYear', Offset(plot.left, plot.bottom + 4), labelStyle);
    _label(canvas, '$maxYear', Offset(plot.right, plot.bottom + 4), labelStyle,
        alignRight: true);

    // The line, broken wherever a year has no record. Gaps are found by the
    // year stepping by more than one.
    final path = Path();
    final area = Path();
    var drawing = false;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final px = x(p.year);
      final py = y(p.median);
      final continues = drawing && points[i - 1].year == p.year - 1;
      if (continues) {
        path.lineTo(px, py);
        area.lineTo(px, py);
      } else {
        if (drawing) {
          area.lineTo(x(points[i - 1].year), plot.bottom);
          area.close();
        }
        path.moveTo(px, py);
        area.moveTo(px, plot.bottom);
        area.lineTo(px, py);
        drawing = true;
      }
    }
    if (drawing) {
      area.lineTo(x(points.last.year), plot.bottom);
      area.close();
    }

    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);

    // A mark per year, sized by how many records stand behind it.
    final most = points.map((p) => p.count).reduce((a, b) => a > b ? a : b);
    for (final p in points) {
      final weight = most == 0 ? 0.0 : p.count / most;
      canvas.drawCircle(
        Offset(x(p.year), y(p.median)),
        2.0 + 2.5 * weight,
        Paint()..color = line,
      );
    }
  }

  static String _format(double v) {
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 1) return v.toStringAsFixed(1);
    return v.toStringAsFixed(3);
  }

  void _label(Canvas canvas, String s, Offset at, TextStyle style,
      {bool alignRight = false}) {
    final painter = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(alignRight ? at.dx - painter.width : at.dx,
          at.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.line != line;
}
