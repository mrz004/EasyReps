import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../core/units.dart';
import '../../core/validation.dart';
import '../../data/database.dart';

sealed class SetEditResult {
  const SetEditResult();
}

class SetEditSave extends SetEditResult {
  const SetEditSave(this.weightKg, this.reps);
  final double weightKg;
  final int reps;
}

class SetEditDelete extends SetEditResult {
  const SetEditDelete();
}

/// Edit or delete one logged set.
class SetEditDialog extends StatefulWidget {
  const SetEditDialog({super.key, required this.set, required this.number, required this.unit});
  final WorkoutSet set;
  final int number;
  final WeightUnit unit;

  @override
  State<SetEditDialog> createState() => _SetEditDialogState();
}

class _SetEditDialogState extends State<SetEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _weight = TextEditingController(
    text: formatWeight(widget.set.weightKg, widget.unit, withUnit: false),
  );
  late final _reps = TextEditingController(text: '${widget.set.reps}');

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final original = formatWeight(widget.set.weightKg, widget.unit, withUnit: false);
    final kg = _weight.text == original
        ? widget.set.weightKg
        : unitToKg(tryParseDecimal(_weight.text)!, widget.unit);
    Navigator.pop(context, SetEditSave(kg, tryParseInt(_reps.text)!));
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete set ${widget.number}?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok && mounted) Navigator.pop(context, const SetEditDelete());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set ${widget.number}'),
      content: Form(
        key: _formKey,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _weight,
                keyboardType: DECIMAL_KEYBOARD,
                inputFormatters: decimalInputFormatters,
                decoration: InputDecoration(labelText: 'Weight (${widget.unit.label})'),
                validator: (v) => weightError(v ?? ''),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _reps,
                keyboardType: TextInputType.number,
                inputFormatters: integerInputFormatters,
                decoration: const InputDecoration(labelText: 'Reps'),
                validator: (v) => repsError(v ?? ''),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          onPressed: _delete,
          child: const Text('Delete'),
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
