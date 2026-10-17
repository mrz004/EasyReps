import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../core/validation.dart';
import '../../data/profile_repository.dart';

sealed class TargetDialogResult {
  const TargetDialogResult();
}

class TargetSave extends TargetDialogResult {
  const TargetSave(this.nutrient, this.value, this.kind);
  final Nutrient nutrient;
  final double value;
  final TargetKind kind;
}

class TargetRemove extends TargetDialogResult {
  const TargetRemove();
}

/// Adds a target ([existing] null; choose from [available]) or edits one.
class TargetDialog extends StatefulWidget {
  const TargetDialog({super.key, this.existing, this.available = const []});
  final Target? existing;
  final List<Nutrient> available;

  @override
  State<TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<TargetDialog> {
  final _formKey = GlobalKey<FormState>();
  late Nutrient _nutrient = widget.existing?.nutrient ?? widget.available.first;
  late TargetKind _kind = widget.existing?.kind ?? _nutrient.defaultKind;
  late final _value = TextEditingController(
    text: widget.existing == null ? '' : formatDecimal(widget.existing!.value),
  );

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, TargetSave(_nutrient, tryParseDecimal(_value.text)!, _kind));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? _nutrient.label : 'Add target'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!editing) ...[
              DropdownButtonFormField<Nutrient>(
                initialValue: _nutrient,
                decoration: const InputDecoration(labelText: 'Nutrient'),
                items: [
                  for (final n in widget.available) DropdownMenuItem(value: n, child: Text(n.label)),
                ],
                onChanged: (n) => setState(() {
                  _nutrient = n!;
                  _kind = n.defaultKind;
                }),
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<TargetKind>(
              segments: [
                for (final k in TargetKind.values) ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _value,
              autofocus: editing,
              keyboardType: DECIMAL_KEYBOARD,
              inputFormatters: decimalInputFormatters,
              decoration: InputDecoration(labelText: 'Value (${_nutrient.unit})'),
              validator: (v) => positiveError(v ?? ''),
            ),
          ],
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, const TargetRemove()),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Asks for a single positive number. Returns null on cancel.
Future<double?> askNumber(
  BuildContext context, {
  required String title,
  required String label,
  double? initial,
}) => showDialog<double>(
  context: context,
  builder: (_) => _NumberDialog(title: title, label: label, initial: initial),
);

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.label, this.initial});
  final String title;
  final String label;
  final double? initial;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _value = TextEditingController(
    text: widget.initial == null ? '' : formatDecimal(widget.initial!),
  );

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _value,
        autofocus: true,
        keyboardType: DECIMAL_KEYBOARD,
        inputFormatters: decimalInputFormatters,
        decoration: InputDecoration(labelText: widget.label),
        validator: (v) => positiveError(v ?? ''),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            Navigator.pop(context, tryParseDecimal(_value.text));
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

/// Body weight for a date (default today). Returns (day, kg).
class BodyWeightDialog extends StatefulWidget {
  const BodyWeightDialog({super.key, required this.unit, this.initialKg});
  final WeightUnit unit;
  final double? initialKg;

  @override
  State<BodyWeightDialog> createState() => _BodyWeightDialogState();
}

class _BodyWeightDialogState extends State<BodyWeightDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _value = TextEditingController(
    text: widget.initialKg == null ? '' : formatWeight(widget.initialKg!, widget.unit, withUnit: false),
  );
  DateTime _day = startOfDay(DateTime.now());

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: startOfDay(DateTime.now()),
    );
    if (picked != null) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add weight'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_today),
            label: Text(formatDayLabel(_day)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _value,
            autofocus: true,
            keyboardType: DECIMAL_KEYBOARD,
            inputFormatters: decimalInputFormatters,
            decoration: InputDecoration(labelText: 'Body weight (${widget.unit.label})'),
            validator: (v) => positiveError(v ?? ''),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final kg = unitToKg(tryParseDecimal(_value.text)!, widget.unit);
          Navigator.pop(context, (day: _day, kg: kg));
        },
        child: const Text('Save'),
      ),
    ],
  );
}
