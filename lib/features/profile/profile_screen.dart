import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../data/database.dart';
import '../../data/profile_repository.dart';
import '../../data/providers.dart';
import '../export/export_dialog.dart';
import 'about_screen.dart';
import 'drive_section.dart';
import 'profile_dialogs.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editTarget(BuildContext context, WidgetRef ref, {Target? existing, List<Nutrient> available = const []}) async {
    final result = await showDialog<TargetDialogResult>(
      context: context,
      builder: (_) => TargetDialog(existing: existing, available: available),
    );
    final profile = ref.read(profileRepositoryProvider);
    switch (result) {
      case TargetSave(:final nutrient, :final value, :final kind):
        await profile.setTarget(nutrient, value, kind);
      case TargetRemove():
        await profile.removeTarget(existing!.nutrient);
      case null:
        break;
    }
  }

  Future<void> _addWeight(BuildContext context, WidgetRef ref, WeightUnit unit, double? latestKg) async {
    final result = await showDialog<({DateTime day, double kg})>(
      context: context,
      builder: (_) => BodyWeightDialog(unit: unit, initialKg: latestKg),
    );
    if (result != null) {
      await ref.read(profileRepositoryProvider).saveBodyWeight(result.day, result.kg);
    }
  }

  void _showWeightHistory(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _WeightHistory(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(targetsProvider).value ?? const <Nutrient, Target>{};
    final unit = ref.watch(currentUnitProvider);
    final height = ref.watch(heightProvider).value;
    final weights = ref.watch(bodyWeightsProvider).value ?? const <BodyWeight>[];
    final latest = weights.firstOrNull;
    final available = Nutrient.values.where((n) => !targets.containsKey(n)).toList();
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionHeader('Nutrition targets'),
          if (targets.isEmpty) const HintText('No targets. Values are shown without goals.', textAlign: TextAlign.start),
          for (final n in Nutrient.values)
            if (targets[n] case final t?)
              _RowCard(
                title: n.label,
                value: '${t.kind.label} ${n.formatWithUnit(t.value)}',
                onTap: () => _editTarget(context, ref, existing: t),
              ),
          if (available.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _editTarget(context, ref, available: available),
              icon: const Icon(Icons.add),
              label: const Text('Add target'),
            ),
          const SectionHeader('Units'),
          Row(
            children: [
              const Expanded(child: Text('Weight')),
              SegmentedButton<WeightUnit>(
                segments: const [
                  ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
                  ButtonSegment(value: WeightUnit.lb, label: Text('lb')),
                ],
                selected: {unit},
                showSelectedIcon: false,
                onSelectionChanged: (s) => ref.read(profileRepositoryProvider).setWeightUnit(s.first),
              ),
            ],
          ),
          const SectionHeader('Body'),
          _RowCard(
            title: 'Height',
            value: height == null ? 'Not set' : '${formatDecimal(height)} cm',
            onTap: () async {
              final cm = await askNumber(context, title: 'Height', label: 'Height (cm)', initial: height);
              if (cm != null) await ref.read(profileRepositoryProvider).setHeightCm(cm);
            },
          ),
          _RowCard(
            title: 'Body weight',
            value: latest == null
                ? 'Not set'
                : '${formatWeight(latest.weightKg, unit)}  (${formatDayLabel(parseDayKey(latest.measuredOn))})',
            onTap: weights.isEmpty ? null : () => _showWeightHistory(context),
          ),
          OutlinedButton.icon(
            onPressed: () => _addWeight(context, ref, unit, latest?.weightKg),
            icon: const Icon(Icons.add),
            label: const Text('Add weight'),
          ),
          const SectionHeader('Google Drive'),
          const DriveSection(),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => showExportDialog(context, format: ExportFormat.pdf),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export PDF summary'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
            child: const Text('About / Licences'),
          ),
          const SizedBox(height: 8),
          Center(child: Text('$APP_NAME $APP_VERSION', style: muted)),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.title, required this.value, this.onTap});
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(value),
        onTap: onTap,
      ),
    ),
  );
}

class _WeightHistory extends ConsumerWidget {
  const _WeightHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weights = ref.watch(bodyWeightsProvider).value ?? const <BodyWeight>[];
    final unit = ref.watch(currentUnitProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Body weight history', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final w in weights)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(formatWeight(w.weightKg, unit)),
                subtitle: Text(formatDate(parseDayKey(w.measuredOn))),
                trailing: IconButton(
                  tooltip: 'Delete entry',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: 'Delete this weight?',
                      confirmLabel: 'Delete',
                      destructive: true,
                    );
                    if (ok) await ref.read(profileRepositoryProvider).deleteBodyWeight(w.id);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
