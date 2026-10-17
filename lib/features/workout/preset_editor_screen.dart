import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../core/validation.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../library/library_screen.dart';

/// Create ([presetId] null), view or edit a preset. "Save as preset" after a
/// Mix session passes [initialExerciseIds].
class PresetEditorScreen extends ConsumerStatefulWidget {
  const PresetEditorScreen({super.key, this.presetId, this.initialExerciseIds = const []});

  final int? presetId;
  final List<String> initialExerciseIds;

  @override
  ConsumerState<PresetEditorScreen> createState() => _PresetEditorScreenState();
}

class _PresetEditorScreenState extends ConsumerState<PresetEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  int _days = 0;
  List<Exercise> _exercises = [];
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _exerciseError;

  bool get _isNew => widget.presetId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final presets = ref.read(presetRepositoryProvider);
    final id = widget.presetId;
    if (id != null) {
      final preset = await presets.byId(id);
      if (preset != null) {
        _name.text = preset.name;
        _days = preset.preferredDays;
        _exercises = await presets.exercisesOf(id);
      }
    } else if (widget.initialExerciseIds.isNotEmpty) {
      _exercises = await ref.read(exerciseRepositoryProvider).byIds(widget.initialExerciseIds);
      _dirty = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _changed(VoidCallback change) => setState(() {
    change();
    _dirty = true;
    _exerciseError = null;
  });

  Future<void> _addFromLibrary() async {
    final picked = await pickExercises(
      context,
      excludedIds: {for (final e in _exercises) e.id},
    );
    if (picked == null || picked.isEmpty) return;
    _changed(() => _exercises = [..._exercises, ...picked]);
  }

  Future<void> _save() async {
    final validName = _formKey.currentState!.validate();
    if (_exercises.isEmpty) setState(() => _exerciseError = 'Add at least one exercise');
    if (!validName || _exercises.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(presetRepositoryProvider).save(
      id: widget.presetId,
      name: _name.text,
      preferredDays: _days,
      exerciseIds: [for (final e in _exercises) e.id],
    );
    if (!mounted) return;
    _dirty = false;
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete preset?',
      message: 'Your logged sessions and sets are kept.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await ref.read(presetRepositoryProvider).delete(widget.presetId!);
    if (!mounted) return;
    _dirty = false;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await confirm(
          context,
          title: 'Discard changes?',
          confirmLabel: 'Discard',
          destructive: true,
        );
        if (discard && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isNew ? 'New preset' : 'Preset')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(key: _formKey, child: _body()),
        bottomNavigationBar: _loading ? null : _actions(),
      ),
    );
  }

  Widget _body() {
    final scheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      buildDefaultDragHandles: false,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Chest Day'),
            validator: (v) => nameError(v ?? ''),
            onChanged: (_) => _dirty = true,
          ),
          const SectionHeader('Preferred days (optional)'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var wd = 1; wd <= 7; wd++)
                FilterChip(
                  label: Text(WEEKDAY_SHORT[wd - 1]),
                  tooltip: WEEKDAY_NAMES[wd - 1],
                  showCheckmark: false,
                  selected: maskHasWeekday(_days, wd),
                  onSelected: (_) => _changed(() => _days ^= weekdayBit(wd)),
                ),
            ],
          ),
          const SectionHeader('Exercises'),
          if (_exercises.isEmpty) const HintText('No exercises yet', textAlign: TextAlign.start),
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_exerciseError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_exerciseError!, style: TextStyle(color: scheme.error)),
              ),
            OutlinedButton.icon(
              onPressed: _addFromLibrary,
              icon: const Icon(Icons.add),
              label: const Text('Add from library'),
            ),
          ],
        ),
      ),
      itemCount: _exercises.length,
      onReorderItem: (from, to) => _changed(() {
        final moved = _exercises.removeAt(from);
        _exercises.insert(to, moved);
      }),
      itemBuilder: (context, i) {
        final e = _exercises[i];
        return Dismissible(
          key: ValueKey(e.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            color: scheme.errorContainer,
            child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
          ),
          onDismissed: (_) => _changed(() => _exercises.removeAt(i)),
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(e.name),
              subtitle: Text(titleCase(e.primaryMuscle)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Remove ${e.name}',
                    icon: const Icon(Icons.close),
                    onPressed: () => _changed(() => _exercises.removeAt(i)),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: Semantics(
                      label: 'Reorder ${e.name}',
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actions() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            if (!_isNew) ...[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: _saving ? null : _delete,
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save preset'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
