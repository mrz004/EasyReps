import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../core/validation.dart';
import '../../data/database.dart';
import '../../data/food_repository.dart';
import '../../data/providers.dart';

/// Creates a custom food with per-100 g values. Pops with the saved [Food].
class CustomFoodScreen extends ConsumerStatefulWidget {
  const CustomFoodScreen({super.key, this.initialName = ''});
  final String initialName;

  @override
  ConsumerState<CustomFoodScreen> createState() => _CustomFoodScreenState();
}

class _CustomFoodScreenState extends ConsumerState<CustomFoodScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _serving = TextEditingController();
  final Map<Nutrient, TextEditingController> _fields = {
    for (final n in Nutrient.values) n: TextEditingController(),
  };
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _serving.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    double? v(Nutrient n) => tryParseDecimal(_fields[n]!.text);
    setState(() => _saving = true);
    final food = await ref.read(foodRepositoryProvider).createCustomFood(
      name: _name.text,
      servingG: tryParseDecimal(_serving.text),
      per100g: NutrientValues(
        kcal: v(Nutrient.kcal)!,
        proteinG: v(Nutrient.proteinG),
        carbsG: v(Nutrient.carbsG),
        sugarG: v(Nutrient.sugarG),
        fiberG: v(Nutrient.fiberG),
        fatG: v(Nutrient.fatG),
        satFatG: v(Nutrient.satFatG),
        sodiumMg: v(Nutrient.sodiumMg),
      ),
    );
    if (mounted) Navigator.pop<Food>(context, food);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom food')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => nameError(v ?? ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _serving,
              keyboardType: DECIMAL_KEYBOARD,
              inputFormatters: decimalInputFormatters,
              decoration: const InputDecoration(labelText: 'Usual serving (g, optional)'),
              validator: (v) => positiveError(v ?? '', required: false),
            ),
            const SectionHeader('Per 100 g'),
            for (final n in Nutrient.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _fields[n],
                  keyboardType: DECIMAL_KEYBOARD,
                  inputFormatters: decimalInputFormatters,
                  decoration: InputDecoration(
                    labelText: n == Nutrient.kcal
                        ? 'Calories (kcal)'
                        : '${n.label} (${n.unit}, optional)',
                  ),
                  validator: (v) => nutrientError(v ?? '', required: n == Nutrient.kcal),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save food'),
          ),
        ),
      ),
    );
  }
}
