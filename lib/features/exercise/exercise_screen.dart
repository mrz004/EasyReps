import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../core/validation.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/session_repository.dart';
import 'rest_timer.dart';
import 'set_edit_dialog.dart';

typedef _SetsKey = ({int sessionId, String exerciseId});

final _exerciseProvider = StreamProvider.autoDispose.family<Exercise?, String>(
  (ref, id) => ref.watch(exerciseRepositoryProvider).watchById(id),
);

final _setsProvider = StreamProvider.autoDispose.family<List<WorkoutSet>, _SetsKey>(
  (ref, key) => ref.watch(sessionRepositoryProvider).watchSets(key.sessionId, key.exerciseId),
);

class ExerciseScreen extends ConsumerStatefulWidget {
  const ExerciseScreen({super.key, required this.sessionId, required this.exerciseId});
  final int sessionId;
  final String exerciseId;

  @override
  ConsumerState<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends ConsumerState<ExerciseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _reps = TextEditingController();
  WorkoutSet? _lastTime;

  /// Exact kg behind the prefilled weight text, so an untouched prefill in lb
  /// does not drift through rounding.
  double? _prefillKg;
  String? _prefillText;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    final last = await ref
        .read(sessionRepositoryProvider)
        .lastEarlierSet(widget.exerciseId, widget.sessionId);
    if (!mounted || last == null) return;
    final unit = await ref.read(weightUnitProvider.future);
    if (!mounted) return;
    setState(() {
      _lastTime = last;
      _setWeightText(last.weightKg, unit);
      _reps.text = '${last.reps}';
    });
  }

  void _setWeightText(double kg, WeightUnit unit) {
    _prefillKg = kg;
    _prefillText = formatWeight(kg, unit, withUnit: false);
    _weight.text = _prefillText!;
  }

  double _enteredKg(WeightUnit unit) {
    if (_weight.text == _prefillText && _prefillKg != null) return _prefillKg!;
    return unitToKg(tryParseDecimal(_weight.text)!, unit);
  }

  Future<void> _addSet(WeightUnit unit) async {
    if (!_formKey.currentState!.validate()) return;
    final kg = _enteredKg(unit);
    final reps = tryParseInt(_reps.text)!;
    setState(() => _adding = true);
    try {
      await ref.read(sessionRepositoryProvider).logSet(
        sessionId: widget.sessionId,
        exerciseId: widget.exerciseId,
        weightKg: kg,
        reps: reps,
      );
      // Boxes keep the values just added.
      _prefillKg = kg;
      _prefillText = _weight.text;
    } on SessionNotActiveException catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editSet(WorkoutSet set, int number, WeightUnit unit) async {
    final action = await showDialog<SetEditResult>(
      context: context,
      builder: (_) => SetEditDialog(set: set, number: number, unit: unit),
    );
    if (action == null || !mounted) return;
    final sessions = ref.read(sessionRepositoryProvider);
    try {
      switch (action) {
        case SetEditDelete():
          await sessions.deleteSet(set.id);
        case SetEditSave(:final weightKg, :final reps):
          await sessions.updateSet(set.id, weightKg: weightKg, reps: reps);
      }
    } on SessionNotActiveException catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(currentUnitProvider);
    final exercise = ref.watch(_exerciseProvider(widget.exerciseId)).value;
    final sets = ref.watch(
      _setsProvider((sessionId: widget.sessionId, exerciseId: widget.exerciseId)),
    ).value ?? const <WorkoutSet>[];
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final muscles = [
      if (exercise != null) titleCase(exercise.primaryMuscle),
      ...?exercise?.secondaryMuscles?.split(',').map((m) => m.trim()).where((m) => m.isNotEmpty),
    ].join(', ');

    return Scaffold(
      appBar: AppBar(title: Text(exercise?.name ?? '')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 3 / 2,
            child: ExerciseImage(asset: exercise?.imageAsset, borderRadius: 12),
          ),
          const SizedBox(height: 12),
          if (muscles.isNotEmpty) Text('$muscles.', style: theme.textTheme.bodyLarge),
          if (exercise?.description != null)
            Text(exercise!.description!, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (_lastTime != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last session: ${formatWeight(_lastTime!.weightKg, unit)} x ${_lastTime!.reps}',
              style: muted,
            ),
          ],
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weight,
                    keyboardType: DECIMAL_KEYBOARD,
                    inputFormatters: decimalInputFormatters,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: 'Weight (${unit.label})'),
                    validator: (v) => weightError(v ?? ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _reps,
                    keyboardType: TextInputType.number,
                    inputFormatters: integerInputFormatters,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: 'Reps'),
                    validator: (v) => repsError(v ?? ''),
                    onFieldSubmitted: (_) => _addSet(unit),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _adding ? null : () => _addSet(unit),
            child: const Text('Add set'),
          ),
          const SizedBox(height: 12),
          RestTimer(sessionId: widget.sessionId),
          const SectionHeader("Today's sets"),
          if (sets.isEmpty) const HintText('No sets yet', textAlign: TextAlign.start),
          for (var i = 0; i < sets.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  title: Text('${i + 1}.  ${formatWeight(sets[i].weightKg, unit)} x ${sets[i].reps}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editSet(sets[i], i + 1, unit),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
