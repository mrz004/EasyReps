import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../core/validation.dart';
import '../../data/database.dart';
import '../../data/food_repository.dart';

sealed class EntryEditorResult {
  const EntryEditorResult();
}

class EntryEditorSave extends EntryEditorResult {
  const EntryEditorSave(this.entry, {this.entryId});
  final FoodEntriesCompanion entry;

  /// Set when editing an existing entry.
  final int? entryId;
}

class EntryEditorDelete extends EntryEditorResult {
  const EntryEditorDelete();
}

/// Edits an existing [entry], or re-adds [template] as a new entry at [eatenAt].
/// Changing the amount rescales all nutrients proportionally.
Future<EntryEditorResult?> showEntryEditor(
  BuildContext context, {
  FoodEntry? entry,
  FoodEntry? template,
  DateTime? eatenAt,
}) {
  assert((entry == null) != (template == null));
  return showModalBottomSheet<EntryEditorResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EntryEditor(
      source: entry ?? template!,
      isEdit: entry != null,
      eatenAt: entry != null ? fromMillis(entry.eatenAt) : eatenAt ?? DateTime.now(),
    ),
  );
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.source, required this.isEdit, required this.eatenAt});
  final FoodEntry source;
  final bool isEdit;
  final DateTime eatenAt;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.source.name);
  late final _quantity = TextEditingController(
    text: widget.source.quantityG == null ? '' : formatDecimal(widget.source.quantityG!),
  );
  late final Map<Nutrient, TextEditingController> _fields = {
    for (final n in Nutrient.values)
      n: TextEditingController(text: _text(NutrientValues.ofEntry(widget.source)[n])),
  };
  late DateTime _eatenAt = widget.eatenAt;

  static String _text(double? v) => v == null ? '' : formatDecimal(v);

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _rescale(String text) {
    final base = widget.source.quantityG;
    final next = tryParseDecimal(text);
    if (base == null || base <= 0 || next == null || next <= 0) return;
    final scaled = NutrientValues.ofEntry(widget.source).scaledBy(next / base);
    for (final n in Nutrient.values) {
      _fields[n]!.text = _text(scaled[n]);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_eatenAt),
    );
    if (picked == null) return;
    setState(() {
      _eatenAt = DateTime(_eatenAt.year, _eatenAt.month, _eatenAt.day, picked.hour, picked.minute);
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    double? v(Nutrient n) => tryParseDecimal(_fields[n]!.text);
    final values = NutrientValues(
      kcal: v(Nutrient.kcal)!,
      proteinG: v(Nutrient.proteinG),
      carbsG: v(Nutrient.carbsG),
      sugarG: v(Nutrient.sugarG),
      fiberG: v(Nutrient.fiberG),
      fatG: v(Nutrient.fatG),
      satFatG: v(Nutrient.satFatG),
      sodiumMg: v(Nutrient.sodiumMg),
    );
    final entry = values.toEntry(
      name: _name.text,
      eatenAt: _eatenAt,
      foodId: widget.source.foodId,
      quantityG: tryParseDecimal(_quantity.text),
    );
    Navigator.pop(context, EntryEditorSave(entry, entryId: widget.isEdit ? widget.source.id : null));
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete "${widget.source.name}"?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok && mounted) Navigator.pop(context, const EntryEditorDelete());
  }

  Widget _numberField(TextEditingController c, String label, {bool required = false, ValueChanged<String>? onChanged, String? Function(String)? validator}) =>
      TextFormField(
        controller: c,
        keyboardType: DECIMAL_KEYBOARD,
        inputFormatters: decimalInputFormatters,
        decoration: InputDecoration(labelText: label),
        validator: (v) => (validator ?? (t) => nutrientError(t, required: required))(v ?? ''),
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final grid = [
      for (final n in Nutrient.values)
        _numberField(
          _fields[n]!,
          n == Nutrient.kcal ? 'Calories (kcal)' : '${n.label} (${n.unit})',
          required: n == Nutrient.kcal,
        ),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isEdit ? 'Edit entry' : 'Add again',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => nameError(v ?? ''),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _numberField(
                      _quantity,
                      'Amount (g)',
                      onChanged: _rescale,
                      validator: (t) => positiveError(t, required: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(formatTime(_eatenAt)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < grid.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: grid[i]),
                      const SizedBox(width: 12),
                      Expanded(child: grid[i + 1]),
                    ],
                  ),
                ),
              Row(
                children: [
                  if (widget.isEdit) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _delete,
                        child: const Text('Delete'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(onPressed: _save, child: const Text('Save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
