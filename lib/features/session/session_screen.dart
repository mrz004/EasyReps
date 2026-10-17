import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../data/session_repository.dart';
import '../exercise/exercise_screen.dart';
import '../library/library_screen.dart';
import '../workout/preset_editor_screen.dart';

final _sessionProvider = StreamProvider.autoDispose.family<Session?, int>(
  (ref, id) => ref.watch(sessionRepositoryProvider).watchById(id),
);

final _sessionExercisesProvider = StreamProvider.autoDispose
    .family<List<SessionExerciseItem>, int>(
      (ref, id) => ref.watch(sessionRepositoryProvider).watchSessionExercises(id),
    );

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, required this.sessionId});
  final int sessionId;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  bool _ending = false;

  Future<void> _addExercise(List<SessionExerciseItem> items) async {
    final picked = await pickExercise(
      context,
      excludedIds: {for (final i in items) i.exercise.id},
    );
    if (picked == null) return;
    try {
      await ref.read(sessionRepositoryProvider).addExercise(widget.sessionId, picked.id);
    } on SessionNotActiveException catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _end() async {
    final ok = await confirm(
      context,
      title: 'End session?',
      message: 'A session with no sets is discarded.',
      confirmLabel: 'End session',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _ending = true);
    final EndResult result;
    try {
      result = await ref.read(sessionRepositoryProvider).end(widget.sessionId);
    } on SessionNotActiveException {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    switch (result) {
      case SessionDiscarded():
        showSnack(context, 'Session discarded (no sets logged)');
        Navigator.pop(context);
      case SessionEnded(wasMix: true, :final exerciseIdsDone):
        final save = await confirm(
          context,
          title: 'Save as preset?',
          message: 'Keep these exercises as a preset for next time.',
          confirmLabel: 'Save as preset',
        );
        if (!mounted) return;
        if (save) {
          await Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PresetEditorScreen(initialExerciseIds: exerciseIdsDone),
            ),
          );
        } else {
          Navigator.pop(context);
        }
      case SessionEnded():
        showSnack(context, 'Session saved');
        Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(_sessionProvider(widget.sessionId));
    final session = sessionAsync.value;
    final itemsAsync = ref.watch(_sessionExercisesProvider(widget.sessionId));
    final items = itemsAsync.value ?? const <SessionExerciseItem>[];
    final isMix = session != null && isMixSession(session);
    final active = session != null && session.endedAt == null;

    return Scaffold(
      appBar: AppBar(title: Text(session?.presetName ?? 'Session')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (sessionAsync.hasValue && !active && !_ending)
            const HintText('This session has ended.'),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: ExerciseImage(asset: item.exercise.imageAsset, size: 48, cacheWidth: 144),
                  title: Text(item.exercise.name),
                  subtitle: Text(titleCase(item.exercise.primaryMuscle)),
                  trailing: Text('${item.setCount} set${item.setCount == 1 ? '' : 's'}'),
                  onTap: active
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ExerciseScreen(
                              sessionId: widget.sessionId,
                              exerciseId: item.exercise.id,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          if (isMix && active) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _addExercise(items),
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
            const SizedBox(height: 8),
            const HintText('Exercises picked here join this session only'),
          ],
          if (!isMix && items.isEmpty && !itemsAsync.isLoading)
            const HintText('This preset has no exercises.'),
        ],
      ),
      bottomNavigationBar: active
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: _ending ? null : _end,
                  child: const Text('End session'),
                ),
              ),
            )
          : null,
    );
  }
}
