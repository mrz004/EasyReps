import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/validation.dart';
import '../../data/providers.dart';

/// Creates a custom exercise (name, primary muscle, optional description).
/// Pops with the created exercise.
class CustomExerciseDialog extends ConsumerStatefulWidget {
  const CustomExerciseDialog({super.key, required this.muscles});
  final List<String> muscles;

  @override
  ConsumerState<CustomExerciseDialog> createState() => _CustomExerciseDialogState();
}

class _CustomExerciseDialogState extends ConsumerState<CustomExerciseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  String? _muscle;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final created = await ref.read(exerciseRepositoryProvider).createCustom(
      name: _name.text,
      primaryMuscle: _muscle!,
      description: _description.text,
    );
    if (mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final muscles = widget.muscles.isEmpty ? const ['other'] : widget.muscles;
    return AlertDialog(
      title: const Text('Custom exercise'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => nameError(v ?? ''),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _muscle,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Primary muscle'),
                items: [
                  for (final m in muscles)
                    DropdownMenuItem(value: m, child: Text(titleCase(m))),
                ],
                onChanged: (v) => setState(() => _muscle = v),
                validator: (v) => v == null ? 'Choose a muscle' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 2,
                maxLength: 140,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _saving ? null : _save,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
