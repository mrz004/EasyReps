import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import 'custom_exercise_dialog.dart';

/// Opens the library picker in single-select mode. Returns the chosen exercise.
Future<Exercise?> pickExercise(BuildContext context, {Set<String> excludedIds = const {}}) =>
    Navigator.push<Exercise>(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryScreen(multiSelect: false, excludedIds: excludedIds),
      ),
    );

/// Opens the library picker in multi-select mode. Returns exercises in pick order.
Future<List<Exercise>?> pickExercises(BuildContext context, {Set<String> excludedIds = const {}}) =>
    Navigator.push<List<Exercise>>(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryScreen(multiSelect: true, excludedIds: excludedIds),
      ),
    );

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, required this.multiSelect, this.excludedIds = const {}});

  final bool multiSelect;

  /// Already in the list being built; shown as "Added" and not selectable.
  final Set<String> excludedIds;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _muscle;
  final List<Exercise> _selected = [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Exercise> _filter(List<Exercise> all) {
    final q = _query.trim().toLowerCase();
    return [
      for (final e in all)
        if ((_muscle == null || e.primaryMuscle == _muscle) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
          e,
    ];
  }

  void _tap(Exercise e) {
    if (widget.excludedIds.contains(e.id)) return;
    if (!widget.multiSelect) {
      Navigator.pop(context, e);
      return;
    }
    setState(() {
      final i = _selected.indexWhere((s) => s.id == e.id);
      i >= 0 ? _selected.removeAt(i) : _selected.add(e);
    });
  }

  Future<void> _createCustom(List<Exercise> all) async {
    final muscles = {for (final e in all) e.primaryMuscle}.toList()..sort();
    final created = await showDialog<Exercise>(
      context: context,
      builder: (_) => CustomExerciseDialog(muscles: muscles),
    );
    if (created == null || !mounted) return;
    if (widget.multiSelect) {
      setState(() => _selected.add(created));
    } else {
      Navigator.pop(context, created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(allExercisesProvider);
    final all = exercisesAsync.value ?? const <Exercise>[];
    final muscles = {for (final e in all) e.primaryMuscle}.toList()..sort();
    final filtered = _filter(all);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.multiSelect ? 'Add exercises' : 'Add exercise'),
        actions: [
          if (widget.multiSelect)
            TextButton(
              onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected),
              child: Text(_selected.isEmpty ? 'Done' : 'Done (${_selected.length})'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search exercises',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final m in muscles)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(titleCase(m)),
                      selected: _muscle == m,
                      onSelected: (on) => setState(() => _muscle = on ? m : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: exercisesAsync.isLoading && all.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.search_off,
                      title: all.isEmpty ? 'No exercises yet' : 'No exercises match',
                      message: all.isEmpty
                          ? 'Create a custom exercise below.'
                          : 'Try another name or clear the muscle filter.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _row(filtered[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: () => _createCustom(all),
            icon: const Icon(Icons.add),
            label: const Text('Custom exercise'),
          ),
        ),
      ),
    );
  }

  Widget _row(Exercise e) {
    final added = widget.excludedIds.contains(e.id);
    final selected = _selected.any((s) => s.id == e.id);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      enabled: !added,
      leading: ExerciseImage(asset: e.imageAsset, size: 56, cacheWidth: 168),
      title: Text(e.name),
      subtitle: Text(titleCase(e.primaryMuscle)),
      trailing: added
          ? const Text('Added')
          : widget.multiSelect
          ? Checkbox(value: selected, onChanged: (_) => _tap(e))
          : null,
      onTap: () => _tap(e),
    );
  }
}
