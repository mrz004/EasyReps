import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../data/providers.dart';
import '../../data/stats_repository.dart';
import '../analyse/analyse_screen.dart';
import '../charts/daily_charts.dart';
import '../food/food_log_screen.dart';
import '../profile/profile_screen.dart';
import '../session/session_launcher.dart';
import '../workout/workout_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _openCoffee(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(COFFEE_URL), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'Could not open the link');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider).value;
    final week = ref.watch(weekVolumeProvider).value;
    final unit = ref.watch(currentUnitProvider);
    final hasVolume = week != null && week.any((d) => d.value > 0);

    return Scaffold(
      appBar: AppBar(title: const Text(APP_NAME)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: SizedBox(
                  height: 200,
                  child: week == null
                      ? const SizedBox.shrink()
                      : hasVolume
                      ? DailyBarChart(
                          values: [for (final d in week) DailyValue(d.day, kgToUnit(d.value, unit))],
                          valueLabel: (v) => '${formatDecimal(v, decimals: 0)} ${unit.label}',
                          semanticLabel: 'Training volume per day for the last 7 days',
                        )
                      : const EmptyChart('Log a set to see your weekly volume'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Your progress this week', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => active != null
                  ? openSession(context, active.id)
                  : startSession(context, ref, null),
              child: Text(active != null ? 'Resume workout' : 'Start workout'),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _Tile('Food', Icons.restaurant, () => _push(context, const FoodLogScreen())),
                _Tile('Workout', Icons.fitness_center, () => _push(context, const WorkoutScreen())),
                _Tile('Analyse', Icons.insights, () => _push(context, const AnalyseScreen())),
                _Tile('Profile', Icons.person_outline, () => _push(context, const ProfileScreen())),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: () => _openCoffee(context),
                child: const Text('Buy me a coffee'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
