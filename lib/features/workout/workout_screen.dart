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

  void _toggle(int id) => setState(() => _expanded = _expanded == id ? null : id);

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
            const Padding(
              padding: EdgeInsets.all(24),
              child: HintText('Tap + to create your first preset'),
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
  const _MixCard({required this.expanded, required this.onTap, required this.onStart});
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
                        TextSpan(text: MIX_NAME.toUpperCase(), style: text.titleMedium),
                        TextSpan(text: '  -  $MIX_TAGLINE', style: text.bodyMedium),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: onStart, child: const Text('Start')),
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

    return LayoutBuilder(
      builder: (context, constraints) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxWidth * 2 / 3),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(summary.preset.name, style: theme.textTheme.titleLarge),
                      ),
                      Text(
                        '#$rank',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(onPressed: onView, child: const Text('View')),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(onPressed: onStart, child: const Text('Start')),
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
    );
  }
}
