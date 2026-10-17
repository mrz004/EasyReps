import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../data/providers.dart';
import '../../data/stats_repository.dart';
import '../charts/daily_charts.dart';
import '../export/export_dialog.dart';

enum AnalyseRange {
  d7('7d', 7),
  d30('30d', 30),
  d90('90d', 90),
  all('All', null);

  const AnalyseRange(this.label, this.days);
  final String label;
  final int? days;

  DayRange toDayRange() => days == null ? DayRange.all() : DayRange.lastDays(days!);
}

typedef _IntakeKey = ({AnalyseRange range, Nutrient nutrient});

final _volumeProvider = StreamProvider.autoDispose.family<List<DailyValue>, AnalyseRange>(
  (ref, range) => ref.watch(statsRepositoryProvider).watchVolumePerDay(range.toDayRange()),
);

final _intakeProvider = StreamProvider.autoDispose.family<List<DailyValue>, _IntakeKey>(
  (ref, key) => ref
      .watch(statsRepositoryProvider)
      .watchIntakePerDay(key.range.toDayRange(), key.nutrient),
);

class AnalyseScreen extends ConsumerStatefulWidget {
  const AnalyseScreen({super.key});

  @override
  ConsumerState<AnalyseScreen> createState() => _AnalyseScreenState();
}

class _AnalyseScreenState extends ConsumerState<AnalyseScreen> {
  final _chartsKey = GlobalKey();
  AnalyseRange _range = AnalyseRange.d30;
  Nutrient _nutrient = Nutrient.kcal;
  bool _sharing = false;

  /// Captures the charts as shown (with titles) and opens the share sheet.
  Future<void> _saveChartImage() async {
    setState(() => _sharing = true);
    try {
      final boundary = _chartsKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/count-my-sweat-${_range.label}-${dayKey(DateTime.now())}.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Could not save the chart: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = ref.watch(currentUnitProvider);
    final volume = ref.watch(_volumeProvider(_range)).value;
    final intake = ref.watch(_intakeProvider((range: _range, nutrient: _nutrient))).value;
    final target = (ref.watch(targetsProvider).value ?? const {})[_nutrient];

    return Scaffold(
      appBar: AppBar(title: const Text('Analyse')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<AnalyseRange>(
            segments: [
              for (final r in AnalyseRange.values)
                ButtonSegment(value: r, label: Text(r.label)),
            ],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: _chartsKey,
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _chartCard(
                    volume == null
                        ? const SizedBox.shrink()
                        : volume.every((d) => d.value == 0)
                        ? const EmptyChart('No sets logged in this range')
                        : DailyLineChart(
                            values: [for (final d in volume) DailyValue(d.day, kgToUnit(d.value, unit))],
                            valueLabel: (v) => '${formatDecimal(v, decimals: 0)} ${unit.label}',
                            semanticLabel: 'Training volume per day, ${_range.label}',
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text('Training volume (${unit.label})', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  _chartCard(
                    intake == null
                        ? const SizedBox.shrink()
                        : intake.every((d) => d.value == 0)
                        ? const EmptyChart('No food logged in this range')
                        : DailyBarChart(
                            values: intake,
                            target: target?.value,
                            valueLabel: _nutrient.formatWithUnit,
                            semanticLabel: 'Daily ${_nutrient.label} intake, ${_range.label}',
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    target == null
                        ? '${_nutrient.label} per day'
                        : '${_nutrient.label} per day vs target (${target.kind.label} '
                              '${_nutrient.formatWithUnit(target.value)})',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              for (final n in Nutrient.values)
                ChoiceChip(
                  label: Text(n.label),
                  selected: _nutrient == n,
                  onSelected: (_) => setState(() => _nutrient = n),
                ),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _sharing ? null : _saveChartImage,
            icon: const Icon(Icons.image_outlined),
            label: const Text('Save chart as image'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showExportDialog(context, format: ExportFormat.csv),
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Export data (CSV)'),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(Widget chart) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: SizedBox(height: 220, child: chart),
    ),
  );
}
