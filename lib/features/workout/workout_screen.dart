import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/ui.dart';
import '../../data/preset_repository.dart';
import '../../data/providers.dart';
import '../session/session_launcher.dart';
import 'preset_editor_screen.dart';

/// Expanded card id: -1 for Mix, a preset id, or null when none is expanded.
const int MIX_CARD_ID = -1;

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  int? _expanded;

  void _toggle(int id) =>
      setState(() => _expanded = _expanded == id ? null : id);

  Future<void> _openEditor({int? presetId}) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PresetEditorScreen(presetId: presetId)),
  );

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(presetSummariesProvider);
    final ranked = rankPresets(summaries.value ?? const [], DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout'),
        actions: [
          IconButton(
            tooltip: 'Create preset',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _MixCard(
            expanded: _expanded == MIX_CARD_ID,
            onTap: () => _toggle(MIX_CARD_ID),
            onStart: () => startSession(context, ref, null),
          ),
          const SizedBox(height: 12),
          if (summaries.hasValue && ranked.isEmpty)
            EmptyState(
              icon: Icons.playlist_add,
              title: 'No presets yet',
              message: 'Save your usual workouts, like Chest Day, and start them in one tap.',
              action: FilledButton.tonalIcon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Create preset'),
              ),
            ),
          for (var i = 0; i < ranked.length; i++) ...[
            _PresetCard(
              rank: i + 1,
              summary: ranked[i],
              expanded: _expanded == ranked[i].preset.id,
              onTap: () => _toggle(ranked[i].preset.id),
              onView: () => _openEditor(presetId: ranked[i].preset.id),
              onStart: () => startSession(context, ref, ranked[i].preset.id),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  const _MixCard({
    required this.expanded,
    required this.onTap,
    required this.onStart,
  });
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxWidth / 5),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: MIX_NAME.toUpperCase(),
                          style: text.titleMedium,
                        ),
                        TextSpan(
                          text: '  -  $MIX_TAGLINE',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onStart,
                        child: const Text('Start'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.rank,
    required this.summary,
    required this.expanded,
    required this.onTap,
    required this.onView,
    required this.onStart,
  });

  final int rank;
  final PresetSummary summary;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onView;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = formatDaysMask(summary.preset.preferredDays);
    final count = summary.exerciseCount;
    final details = [
      if (days.isNotEmpty) days,
      '$count exercise${count == 1 ? '' : 's'}',
    ].join('  -  ');

    final scheme = theme.colorScheme;
    final names = summary.exerciseNames;
    const previewCount = 4;

    return LayoutBuilder(
      builder: (context, constraints) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            // About 3:2; IntrinsicHeight lets the Spacer push the exercise
            // preview to the bottom of that minimum height.
            constraints: BoxConstraints(
              minHeight: constraints.maxWidth * 2 / 3,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            summary.preset.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Text(
                              '#$rank',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (names.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final name in names.take(previewCount))
                            _ExerciseChip(name),
                          if (names.length > previewCount)
                            _ExerciseChip(
                              '+${names.length - previewCount} more',
                              muted: true,
                            ),
                        ],
                      ),
                    ],
                    if (expanded) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onView,
                              child: const Text('View'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: onStart,
                              child: const Text('Start'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small tag showing one exercise of a preset.
class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip(this.label, {this.muted = false});
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted ? Colors.transparent : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: muted ? Border.all(color: scheme.outlineVariant) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: muted
                ? scheme.onSurfaceVariant
                : scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
