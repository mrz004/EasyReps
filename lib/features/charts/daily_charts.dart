import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/units.dart';
import '../../data/stats_repository.dart';

String _compact(double v) {
  if (v >= 1000000) return '${formatDecimal(v / 1000000)}M';
  if (v >= 1000) return '${formatDecimal(v / 1000)}k';
  return formatDecimal(v, decimals: 0);
}

String _dayAxisLabel(DateTime day, int pointCount) =>
    pointCount <= 7 ? WEEKDAY_SHORT[day.weekday - 1] : '${day.day}/${day.month}';

/// Interval between labelled points so the bottom axis stays readable.
int _labelStep(int count) => max(1, (count / 6).ceil());

/// Bar chart of one value per day, with an optional horizontal target line.
class DailyBarChart extends StatelessWidget {
  const DailyBarChart({
    super.key,
    required this.values,
    this.target,
    this.valueLabel,
    this.semanticLabel,
  });

  final List<DailyValue> values;
  final double? target;
  final String Function(double)? valueLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = values.fold<double>(target ?? 0, (m, v) => max(m, v.value));
    final step = _labelStep(values.length);
    final barWidth = values.isEmpty ? 8.0 : (220 / values.length).clamp(2.0, 18.0);
    return Semantics(
      label: semanticLabel,
      child: BarChart(
        BarChartData(
          maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
          minY: 0,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${formatShortDate(values[group.x].day)}\n'
                '${valueLabel?.call(rod.toY) ?? formatDecimal(rod.toY)}',
                TextStyle(color: scheme.onInverseSurface),
              ),
              getTooltipColor: (_) => scheme.inverseSurface,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, meta) => v == meta.max
                    ? const SizedBox.shrink()
                    : Text(_compact(v), style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= values.length || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    _dayAxisLabel(values[i].day, values.length),
                    style: Theme.of(context).textTheme.labelSmall,
                  );
                },
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (target != null)
                HorizontalLine(
                  y: target!,
                  color: scheme.tertiary,
                  strokeWidth: 2,
                  dashArray: [6, 4],
                ),
            ],
          ),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i].value,
                    width: barWidth,
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(min(4, barWidth / 2)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Line chart of one value per day.
class DailyLineChart extends StatelessWidget {
  const DailyLineChart({
    super.key,
    required this.values,
    this.valueLabel,
    this.semanticLabel,
  });

  final List<DailyValue> values;
  final String Function(double)? valueLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = values.fold<double>(0, (m, v) => max(m, v.value));
    final step = _labelStep(values.length);
    return Semantics(
      label: semanticLabel,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
          minX: 0,
          maxX: max(1, values.length - 1).toDouble(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${formatShortDate(values[s.x.toInt()].day)}\n'
                    '${valueLabel?.call(s.y) ?? formatDecimal(s.y)}',
                    TextStyle(color: scheme.onInverseSurface),
                  ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, meta) => v == meta.max
                    ? const SizedBox.shrink()
                    : Text(_compact(v), style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (v != i || i < 0 || i >= values.length || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    _dayAxisLabel(values[i].day, values.length),
                    style: Theme.of(context).textTheme.labelSmall,
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i].value),
              ],
              color: scheme.primary,
              barWidth: 3,
              isCurved: false,
              dotData: FlDotData(show: values.length <= 31),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shown inside a chart box when there is nothing to plot.
class EmptyChart extends StatelessWidget {
  const EmptyChart(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
