import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/chart_palette.dart';
import '../../../../config/theme/spacing.dart';

/// The marks every console chart is drawn from.
///
/// ALL HAND-PAINTED, DELIBERATELY. A charting package is 300KB–2MB of Dart for
/// three shapes, against a 2MB per-dependency budget and a web bundle that is
/// already 5.8MB. These are a few hundred lines of CustomPainter and they use
/// the app's own tokens, which no package would.
///
/// They follow the dataviz mark spec rather than my taste: thin marks, a 2px
/// SURFACE-COLOURED GAP between adjacent fills, rounded data-ends, recessive
/// grid ink, and direct labels in text ink rather than the series colour. The
/// gap is not decoration — the palette's blue and green separate by ΔE ~3.5
/// under tritanopia, so two touching fills would read as one shape without it.

// ---------------------------------------------------------------------------
// Ring
// ---------------------------------------------------------------------------

/// One slice of a ring.
class RingSlice {
  final String label;
  final num value;
  final Color color;
  const RingSlice({required this.label, required this.value, required this.color});
}

/// A part-to-whole ring with the total in the middle.
///
/// A ring is the right mark for a SMALL NUMBER OF PARTS OF ONE KNOWN WHOLE and
/// almost nothing else. Two or three slices of a total the reader already
/// understands — beds, seats, sessions — read instantly. Four uneven categories
/// do not: the eye cannot compare arc lengths that do not share a baseline, and
/// the reader ends up matching colours to a legend one at a time. That is what
/// bars are for, and why the role breakdown is not a donut.
class RingChart extends StatelessWidget {
  final List<RingSlice> slices;
  final String centerLabel;
  final String centerValue;

  /// Stroke thickness. The default is a genuine ring; anything much fatter
  /// becomes a pie with a hole and loses the arc-length read.
  final double stroke;

  const RingChart({
    super.key,
    required this.slices,
    required this.centerLabel,
    required this.centerValue,
    this.stroke = 16,
  });

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, x) => s + x.value.toDouble());
    return LayoutBuilder(builder: (context, box) {
      final d = math.min(box.maxWidth, box.maxHeight);
      return Center(
        child: SizedBox(
          width: d,
          height: d,
          child: CustomPaint(
            painter: RingPainter(
              slices: slices,
              total: total,
              stroke: stroke,
              track: ChartPalette.grid(context),
              // The gap is painted in the SURFACE colour, so it reads as the
              // card showing through rather than as a fifth grey slice.
              gap: AppColors.surfaceOf(context),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerValue,
                      maxLines: 1,
                      style: AppTextStyles.numericLarge.copyWith(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w800)),
                  // Reported live as "the number sits above centre, not in
                  // it": an empty centerLabel ('' -- a caller with nothing to
                  // caption the ring with) still rendered a Text widget, and
                  // an empty string still occupies a full line of height. The
                  // Column (mainAxisSize.min) then measured value-line +
                  // blank-line, and Center centred THAT taller box -- so the
                  // visible number sat above the ring's true centre by
                  // roughly half the phantom line's height. Omitting the
                  // widget entirely when there is nothing to show fixes every
                  // ring with a blank label at once, not just one call site.
                  if (centerLabel.isNotEmpty)
                    Text(centerLabel,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textSecondaryOf(context))),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class RingPainter extends CustomPainter {
  final List<RingSlice> slices;
  final double total;
  final double stroke;
  final Color track;
  final Color gap;

  const RingPainter({
    required this.slices,
    required this.total,
    required this.stroke,
    required this.track,
    required this.gap,
  });

  static const _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);

    Paint pen(Color c, [double? w]) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w ?? stroke
      ..strokeCap = StrokeCap.butt;

    // Track first, so a zero-value slice leaves a complete ring rather than a
    // hole that reads as missing data.
    canvas.drawArc(rect, 0, _tau, false, pen(track));
    if (total <= 0) return;

    var start = -math.pi / 2;
    for (final s in slices) {
      final sweep = _tau * (s.value.toDouble() / total);
      if (sweep <= 0) continue;
      canvas.drawArc(rect, start, sweep, false, pen(s.color));
      start += sweep;
    }

    // The 2px separators, painted last so they cut every boundary cleanly.
    // Skipped for a single slice, which has no boundary to cut.
    if (slices.where((s) => s.value > 0).length > 1) {
      var edge = -math.pi / 2;
      for (final s in slices) {
        final sweep = _tau * (s.value.toDouble() / total);
        if (sweep <= 0) continue;
        canvas.drawArc(rect, edge - 0.012, 0.024, false, pen(gap, stroke + 2));
        edge += sweep;
      }
    }
  }

  @override
  bool shouldRepaint(covariant RingPainter old) =>
      old.total != total ||
      old.stroke != stroke ||
      old.track != track ||
      old.gap != gap ||
      old.slices.length != slices.length ||
      _valuesDiffer(old.slices, slices);

  static bool _valuesDiffer(List<RingSlice> a, List<RingSlice> b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i].value != b[i].value || a[i].color != b[i].color) return true;
    }
    return false;
  }
}

/// The legend for a ring, carrying the NUMBERS and not only the colours.
///
/// Mandatory beside any ring whose slices can be thin. Hall occupancy runs at
/// 3 of 2800 beds — a slice 0.1% of a circle is invisible at any size, so
/// without the value in text the chart says nothing at all.
class ChartLegend extends StatelessWidget {
  final List<RingSlice> slices;
  final String Function(num)? format;

  const ChartLegend({super.key, required this.slices, this.format});

  @override
  Widget build(BuildContext context) {
    final fmt = format ?? (n) => '$n';
    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.xs,
      alignment: WrapAlignment.center,
      children: [
        for (final s in slices)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpace.xs),
            Text('${s.label} ',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context))),
            Text(fmt(s.value),
                style: AppTextStyles.numericSmall
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bars
// ---------------------------------------------------------------------------

class BarDatum {
  final String label;
  final num value;
  const BarDatum(this.label, this.value);
}

/// Labelled horizontal bars — the default for comparing magnitude.
///
/// Horizontal rather than vertical because these categories have real names
/// ("Staff/Officer", "Software Engineering") and a vertical axis would either
/// rotate them 45 degrees or truncate them. The label, the count and the share
/// sit on one line, so the chart is readable in greyscale and to a screen
/// reader — colour is confirmation here, never the carrier.
///
/// Folds past [ChartPalette.seats] into a single "Other" row rather than
/// cycling hues, because two different things wearing the same colour is worse
/// than an honest grey.
class BarList extends StatelessWidget {
  final List<BarDatum> data;
  final int? total;
  final int maxRows;

  const BarList({
    super.key,
    required this.data,
    this.total,
    this.maxRows = ChartPalette.seats,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final sorted = [...data]..sort((a, b) => b.value.compareTo(a.value));
    final shown = <BarDatum>[];
    if (sorted.length <= maxRows) {
      shown.addAll(sorted);
    } else {
      shown.addAll(sorted.take(maxRows - 1));
      final rest = sorted.skip(maxRows - 1).fold<num>(0, (s, d) => s + d.value);
      shown.add(BarDatum('Other', rest));
    }

    final sum = total ?? sorted.fold<num>(0, (s, d) => s + d.value).toInt();
    final max = shown.first.value <= 0 ? 1 : shown.first.value;
    final folded = sorted.length > maxRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          _Bar(
            datum: shown[i],
            max: max,
            total: sum,
            color: (folded && i == shown.length - 1)
                ? ChartPalette.muted(context)
                : ChartPalette.series(context, i),
          ),
          if (i != shown.length - 1) const SizedBox(height: AppSpace.sm),
        ],
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final BarDatum datum;
  final num max;
  final num total;
  final Color color;

  const _Bar({
    required this.datum,
    required this.max,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0 : (datum.value * 100 / total).round();
    return Semantics(
      label: '${datum.label}: ${datum.value} of $total, $share percent',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(datum.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ),
          const SizedBox(width: AppSpace.sm),
          Text('${datum.value}',
              style: AppTextStyles.numericSmall
                  .copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(width: AppSpace.xs),
          SizedBox(
            width: 38,
            child: Text('$share%',
                textAlign: TextAlign.end,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context))),
          ),
        ]),
        const SizedBox(height: 3),
        // 6px is the "thin mark" the spec asks for — a bar thick enough to
        // read as a quantity and thin enough not to shout over its own label.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(children: [
              Positioned.fill(
                  child: ColoredBox(color: ChartPalette.grid(context))),
              FractionallySizedBox(
                widthFactor: (datum.value / max).clamp(0.0, 1.0).toDouble(),
                child: ColoredBox(color: color),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Heat grid
// ---------------------------------------------------------------------------

/// A day x slot density grid — the right mark for "when is this place busy".
///
/// Uses the SEQUENTIAL ramp, not the categorical palette: every cell answers
/// the same question with a different magnitude, so one hue getting darker is
/// the whole encoding. A categorical grid here would ask the reader to decode
/// a legend for all 60-odd cells.
class HeatGrid extends StatelessWidget {
  /// `values[row][col]`. Rows are the y labels, columns the x labels.
  final List<List<num>> values;
  final List<String> rowLabels;
  final List<String> colLabels;

  const HeatGrid({
    super.key,
    required this.values,
    required this.rowLabels,
    required this.colLabels,
  });

  @override
  Widget build(BuildContext context) {
    var max = 0.0;
    for (final row in values) {
      for (final v in row) {
        if (v > max) max = v.toDouble();
      }
    }

    final secondary = AppColors.textSecondaryOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 34,
            child: Column(children: [
              for (final r in rowLabels)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(r,
                        maxLines: 1,
                        style: AppTextStyles.labelSmall.copyWith(color: secondary)),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Column(children: [
              for (var r = 0; r < values.length; r++)
                Expanded(
                  // stretch, NOT the default center. `Expanded` only makes the
                  // MAIN axis tight; on the cross axis a centered child gets
                  // LOOSE constraints, and a DecoratedBox with no child takes
                  // the minimum it is allowed — zero height. Every cell then
                  // painted at 0px: no overflow, no error, no cells, and the
                  // row and column labels still drew perfectly around the void.
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var c = 0; c < values[r].length; c++)
                      Expanded(
                        child: Padding(
                          // The 1px inset on every side is the 2px surface gap
                          // between neighbours, so the grid reads as cells
                          // rather than as one continuous wash.
                          padding: const EdgeInsets.all(1),
                          child: Semantics(
                            label: '${rowLabels[r]} '
                                '${c < colLabels.length ? colLabels[c] : ''}: '
                                '${values[r][c]}',
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: ChartPalette.rampStep(
                                    context, values[r][c], max),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: AppSpace.xs),
      Row(children: [
        const SizedBox(width: 34),
        Expanded(
          child: Row(children: [
            for (final c in colLabels)
              Expanded(
                child: Text(c,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.labelSmall.copyWith(color: secondary)),
              ),
          ]),
        ),
      ]),
    ]);
  }
}
