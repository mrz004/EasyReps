import 'package:flutter/material.dart';

import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../core/validation.dart';
import '../../data/database.dart';
import '../../data/food_repository.dart';

/// Asks for the amount eaten of [food] with a live nutrient preview.
/// Returns the entry to insert (nutrients copied at save time).
Future<FoodEntriesCompanion?> showFoodAmountSheet(
  BuildContext context, {
  required Food food,
  required DateTime eatenAt,
}) => showModalBottomSheet<FoodEntriesCompanion>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _FoodAmountSheet(food: food, eatenAt: eatenAt),
);

class _FoodAmountSheet extends StatefulWidget {
  const _FoodAmountSheet({required this.food, required this.eatenAt});
  final Food food;
  final DateTime eatenAt;

  @override
  State<_FoodAmountSheet> createState() => _FoodAmountSheetState();
}

class _FoodAmountSheetState extends State<_FoodAmountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: formatDecimal(widget.food.servingG ?? 100));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final grams = tryParseDecimal(_amount.text)!;
    final values = NutrientValues.ofFood(widget.food).scaledTo(grams);
    final name = widget.food.brand == null
        ? widget.food.name
        : '${widget.food.name} (${widget.food.brand})';
    Navigator.pop(
      context,
      values.toEntry(name: name, eatenAt: widget.eatenAt, foodId: widget.food.id, quantityG: grams),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grams = tryParseDecimal(_amount.text);
    final preview = grams == null || grams <= 0
        ? null
        : NutrientValues.ofFood(widget.food).scaledTo(grams);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.food.name, style: theme.textTheme.titleLarge),
              if (widget.food.brand != null)
                Text(widget.food.brand!, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: DECIMAL_KEYBOARD,
                inputFormatters: decimalInputFormatters,
                decoration: const InputDecoration(labelText: 'Amount (g)'),
                validator: (v) => positiveError(v ?? ''),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 12),
              if (preview != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (final n in Nutrient.values)
                          if (preview[n] != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(child: Text(n.label)),
                                  Text(n.formatWithUnit(preview[n]!)),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _save, child: const Text('Save')),
              if (widget.food.source == 'off') ...[
                const SizedBox(height: 8),
                const HintText('Data from Open Food Facts (ODbL)'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
