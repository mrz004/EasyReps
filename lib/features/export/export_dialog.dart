import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/providers.dart';
import '../../data/stats_repository.dart';
import 'export_service.dart';

export 'export_service.dart' show ExportFormat;

Future<void> showExportDialog(BuildContext context, {required ExportFormat format}) =>
    showDialog(context: context, builder: (_) => ExportDialog(format: format));

enum _RangeChoice {
  d7('7d', 7),
  d30('30d', 30),
  d90('90d', 90),
  all('All', null),
  custom('Custom', null);

  const _RangeChoice(this.label, this.days);
  final String label;
  final int? days;
}

/// Shared export dialog: date range + Workout / Food checkboxes.
class ExportDialog extends ConsumerStatefulWidget {
  const ExportDialog({super.key, required this.format});
  final ExportFormat format;

  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  _RangeChoice _choice = _RangeChoice.d30;
  DateTimeRange? _custom;
  bool _workout = true;
  bool _food = true;
  bool _busy = false;
  String? _message;

  DayRange get _range => switch (_choice) {
    _RangeChoice.all => DayRange.all(),
    _RangeChoice.custom => DayRange(_custom!.start, _custom!.end),
    _ => DayRange.lastDays(_choice.days!),
  };

  Future<void> _pickCustom() async {
    final today = startOfDay(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: _custom ?? DateTimeRange(start: addDays(today, -29), end: today),
    );
    if (picked == null) return;
    setState(() {
      _custom = picked;
      _choice = _RangeChoice.custom;
      _message = null;
    });
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final exported = await ExportService(ref.read(databaseProvider)).run(
        ExportRequest(
          format: widget.format,
          range: _range,
          includeWorkout: _workout,
          includeFood: _food,
        ),
      );
      if (!mounted) return;
      if (exported) {
        Navigator.pop(context);
      } else {
        setState(() => _message = 'Nothing to export in this range.');
      }
    } on Object catch (e) {
      if (mounted) setState(() => _message = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canExport = (_workout || _food) && !_busy;
    return AlertDialog(
      title: Text(widget.format == ExportFormat.csv ? 'Export data (CSV)' : 'Export PDF summary'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Date range', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in _RangeChoice.values.where((c) => c != _RangeChoice.custom))
                  ChoiceChip(
                    label: Text(c.label),
                    selected: _choice == c,
                    onSelected: (_) => setState(() {
                      _choice = c;
                      _message = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 48),
                backgroundColor: _choice == _RangeChoice.custom
                    ? theme.colorScheme.secondaryContainer
                    : null,
              ),
              onPressed: _pickCustom,
              child: Text(
                _choice == _RangeChoice.custom && _custom != null
                    ? '${formatShortDate(_custom!.start)} - ${formatShortDate(_custom!.end)}'
                    : 'Custom range...',
              ),
            ),
            const SizedBox(height: 16),
            Text('Include', style: theme.textTheme.titleSmall),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Workout'),
              value: _workout,
              onChanged: (v) => setState(() => _workout = v!),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Food'),
              value: _food,
              onChanged: (v) => setState(() => _food = v!),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_message!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: canExport ? _export : null,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Export'),
        ),
      ],
    );
  }
}
