import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colours shared by the export charts (validated categorical slots 1-2).
abstract final class ExportChartColors {
  static const median = Color(0xFF2A78D6);
  static const worst = Color(0xFFEB6834);
  static const threshold = Color(0xFFC0392B);
  static const opened = Color(0xFFEDA100);
}

/// A small dependency-free line chart: median journey (solid), worst case
/// (dashed), an optional threshold and the unpacking period shaded.
/// Touch or drag to read the values at a given hour.
class TimelineChart extends StatefulWidget {
  const TimelineChart({
    required this.title,
    required this.unit,
    required this.hours,
    required this.median,
    this.worst,
    this.worstHours,
    this.threshold,
    this.thresholdLabel,
    this.openedAtHour,
    this.minY,
    this.maxY,
    this.decimals = 1,
    this.xLabel = 'hours',
    this.height = 200,
    super.key,
  });

  final String title;
  final String unit;
  final List<double> hours;
  final List<double?> median;
  final List<double?>? worst;
  final List<double>? worstHours;
  final double? threshold;
  final String? thresholdLabel;
  final double? openedAtHour;
  final double? minY;
  final double? maxY;
  final int decimals;
  final String xLabel;
  final double height;

  @override
  State<TimelineChart> createState() => _TimelineChartState();
}

class _TimelineChartState extends State<TimelineChart> {
  double? _selectedX;

  double? _valueAt(List<double> xs, List<double?> ys, double x) {
    if (xs.isEmpty) return null;
    var best = 0;
    for (var i = 1; i < xs.length && i < ys.length; i++) {
      if ((xs[i] - x).abs() < (xs[best] - x).abs()) best = i;
    }
    return best < ys.length ? ys[best] : null;
  }

  void _select(Offset local, Size size) {
    final range = _ChartGeometry.of(widget, size);
    if (range == null) return;
    final x = range.xFromPixel(local.dx);
    setState(() => _selectedX = x.clamp(range.minX, range.maxX).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedX;
    var readout = 'Touch the chart to read values';
    if (selected != null) {
      final median = _valueAt(widget.hours, widget.median, selected);
      final worst = widget.worst == null
          ? null
          : _valueAt(
              widget.worstHours ?? widget.hours,
              widget.worst!,
              selected,
            );
      final parts = <String>['${selected.toStringAsFixed(0)} ${widget.xLabel}'];
      if (median != null) {
        parts.add('median ${median.toStringAsFixed(widget.decimals)}');
      }
      if (worst != null) {
        parts.add('worst ${worst.toStringAsFixed(widget.decimals)}');
      }
      readout = '${parts.join(' · ')} ${widget.unit}';
    }

    return Semantics(
      label: '${widget.title} chart',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            readout,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, widget.height);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _select(details.localPosition, size),
                  onHorizontalDragUpdate: (details) =>
                      _select(details.localPosition, size),
                  child: CustomPaint(
                    size: size,
                    painter: _TimelinePainter(
                      chart: widget,
                      selectedX: _selectedX,
                      textColor: theme.colorScheme.onSurfaceVariant,
                      gridColor: theme.colorScheme.outlineVariant,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              const _LegendItem(
                color: ExportChartColors.median,
                label: 'Median journey',
              ),
              if (widget.worst != null)
                const _LegendItem(
                  color: ExportChartColors.worst,
                  label: 'Worst case',
                  dashed: true,
                ),
              if (widget.threshold != null)
                _LegendItem(
                  color: ExportChartColors.threshold,
                  label: widget.thresholdLabel ?? 'Limit',
                  dashed: true,
                ),
              if (widget.openedAtHour != null)
                const _LegendItem(
                  color: ExportChartColors.opened,
                  label: 'Bag opened',
                  block: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.dashed = false,
    this.block = false,
  });

  final Color color;
  final String label;
  final bool dashed;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: block ? 10 : 3,
          decoration: BoxDecoration(
            color: block ? color.withValues(alpha: 0.3) : color,
            borderRadius: BorderRadius.circular(2),
          ),
          child: dashed
              ? Row(
                  children: [
                    const Spacer(),
                    Container(width: 3, color: theme.colorScheme.surface),
                    const Spacer(),
                  ],
                )
              : null,
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ChartGeometry {
  _ChartGeometry({
    required this.size,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  static const left = 44.0;
  static const right = 8.0;
  static const top = 6.0;
  static const bottom = 22.0;

  final Size size;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  static _ChartGeometry? of(TimelineChart chart, Size size) {
    final xs = [...chart.hours, ...?chart.worstHours];
    if (xs.isEmpty) return null;
    final values = <double>[
      ...chart.median.whereType<double>(),
      ...?chart.worst?.whereType<double>(),
      if (chart.threshold != null) chart.threshold!,
    ];
    if (values.isEmpty) return null;
    var lo = chart.minY ?? values.reduce(math.min);
    var hi = chart.maxY ?? values.reduce(math.max);
    if (chart.minY == null && lo > 0 && lo < (hi - lo)) lo = 0;
    if (hi - lo < 1e-9) {
      hi = lo + (lo.abs() < 1 ? 1 : lo.abs() * 0.1);
    }
    if (chart.maxY == null) hi += (hi - lo) * 0.05;
    return _ChartGeometry(
      size: size,
      minX: xs.reduce(math.min),
      maxX: math.max(xs.reduce(math.max), xs.reduce(math.min) + 1),
      minY: lo,
      maxY: hi,
    );
  }

  double get plotWidth => math.max(size.width - left - right, 1);
  double get plotHeight => math.max(size.height - top - bottom, 1);

  double px(double x) => left + (x - minX) / (maxX - minX) * plotWidth;
  double py(double y) => top + (1 - (y - minY) / (maxY - minY)) * plotHeight;
  double xFromPixel(double pixel) =>
      minX + (pixel - left) / plotWidth * (maxX - minX);
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.chart,
    required this.selectedX,
    required this.textColor,
    required this.gridColor,
  });

  final TimelineChart chart;
  final double? selectedX;
  final Color textColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _ChartGeometry.of(chart, size);
    if (g == null) return;

    final opened = chart.openedAtHour;
    if (opened != null) {
      canvas.drawRect(
        Rect.fromLTRB(
          g.px(opened),
          _ChartGeometry.top,
          g.px(g.maxX),
          _ChartGeometry.top + g.plotHeight,
        ),
        Paint()..color = ExportChartColors.opened.withValues(alpha: 0.15),
      );
    }

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final value = g.minY + (g.maxY - g.minY) * i / 4;
      final y = g.py(value);
      canvas.drawLine(Offset(_ChartGeometry.left, y), Offset(g.px(g.maxX), y), grid);
      _text(canvas, _format(value), Offset(_ChartGeometry.left - 6, y), alignRight: true);
    }
    final step = _niceStep(g.maxX - g.minX);
    for (var x = (g.minX / step).ceil() * step; x <= g.maxX + 1e-9; x += step) {
      _text(
        canvas,
        x.toStringAsFixed(0),
        Offset(g.px(x), _ChartGeometry.top + g.plotHeight + 4),
        center: true,
      );
    }

    final threshold = chart.threshold;
    if (threshold != null && threshold >= g.minY && threshold <= g.maxY) {
      _dashedLine(
        canvas,
        Offset(_ChartGeometry.left, g.py(threshold)),
        Offset(g.px(g.maxX), g.py(threshold)),
        Paint()
          ..color = ExportChartColors.threshold
          ..strokeWidth = 1.5,
      );
    }

    final worst = chart.worst;
    if (worst != null) {
      final path = _path(g, chart.worstHours ?? chart.hours, worst);
      _dashedPath(
        canvas,
        path,
        Paint()
          ..color = ExportChartColors.worst
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    canvas.drawPath(
      _path(g, chart.hours, chart.median),
      Paint()
        ..color = ExportChartColors.median
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    final selected = selectedX;
    if (selected != null) {
      canvas.drawLine(
        Offset(g.px(selected), _ChartGeometry.top),
        Offset(g.px(selected), _ChartGeometry.top + g.plotHeight),
        Paint()
          ..color = textColor
          ..strokeWidth = 1,
      );
    }
  }

  Path _path(_ChartGeometry g, List<double> xs, List<double?> ys) {
    final path = Path();
    var drawing = false;
    for (var i = 0; i < xs.length && i < ys.length; i++) {
      final y = ys[i];
      if (y == null) {
        drawing = false;
        continue;
      }
      final point = Offset(g.px(xs[i]), g.py(y.clamp(g.minY, g.maxY).toDouble()));
      if (drawing) {
        path.lineTo(point.dx, point.dy);
      } else {
        path.moveTo(point.dx, point.dy);
        drawing = true;
      }
    }
    return path;
  }

  void _dashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 6, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 4;
      }
    }
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    _dashedPath(
      canvas,
      Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy),
      paint..style = PaintingStyle.stroke,
    );
  }

  void _text(
    Canvas canvas,
    String text,
    Offset anchor, {
    bool alignRight = false,
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = anchor.dx;
    var dy = anchor.dy;
    if (alignRight) {
      dx -= painter.width;
      dy -= painter.height / 2;
    } else if (center) {
      dx -= painter.width / 2;
    }
    painter.paint(canvas, Offset(dx, dy));
  }

  static String _format(double value) {
    final magnitude = value.abs();
    if (magnitude >= 100) return value.toStringAsFixed(0);
    if (magnitude >= 10) return value.toStringAsFixed(1);
    if (magnitude >= 1) return value.toStringAsFixed(2);
    return value.toStringAsFixed(3);
  }

  static double _niceStep(double span) {
    for (final step in [1.0, 2.0, 6.0, 12.0, 24.0]) {
      if (span / step <= 8) return step;
    }
    return 48;
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.chart != chart ||
      oldDelegate.selectedX != selectedX ||
      oldDelegate.textColor != textColor;
}
