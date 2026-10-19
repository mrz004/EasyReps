import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Re-enable with the coffee link below once COFFEE_URL is set up.
// import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/glass.dart';
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

  // "Buy me a coffee" is hidden until COFFEE_URL points at the owner's page.
  // To restore it: uncomment this method, the url_launcher import above and
  // the link at the bottom of build().
  //
  // Future<void> _openCoffee(BuildContext context) async {
  //   final ok = await launchUrl(Uri.parse(COFFEE_URL), mode: LaunchMode.externalApplication);
  //   if (!ok && context.mounted) showSnack(context, 'Could not open the link');
  // }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider).value;
    final week = ref.watch(weekVolumeProvider).value;
    final unit = ref.watch(currentUnitProvider);
    final hasVolume = week != null && week.any((d) => d.value > 0);
    final weekTotalKg = week?.fold<double>(0, (sum, d) => sum + d.value) ?? 0;
    const gap = SizedBox.square(dimension: 12);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [AppLogo(size: 34), SizedBox(width: 10), Text(APP_NAME)],
        ),
      ),
      body: SafeArea(
        // Everything fits one screen: spare height goes to the chart (5) and
        // the tiles (4). With large text the page scrolls instead of squashing.
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _WeekCard(
                        header: 'Your progress this week',
                        total: hasVolume
                            ? '${formatDecimal(kgToUnit(weekTotalKg, unit), decimals: 0)} ${unit.label}'
                            : null,
                        chart: week == null
                            ? const SizedBox.shrink()
                            : hasVolume
                            ? DailyBarChart(
                                values: [
                                  for (final d in week)
                                    DailyValue(d.day, kgToUnit(d.value, unit)),
                                ],
                                valueLabel: (v) =>
                                    '${formatDecimal(v, decimals: 0)} ${unit.label}',
                                semanticLabel: 'Training volume per day for the last 7 days',
                              )
                            : const EmptyChart(
                                'Log a set to see your weekly volume',
                                icon: Icons.bar_chart,
                              ),
                      ),
                    ),
                    gap,
                    FilledButton.icon(
                      onPressed: () => active != null
                          ? openSession(context, active.id)
                          : startSession(context, ref, null),
                      icon: Icon(
                        active != null
                            ? Icons.play_arrow_rounded
                            : Icons.fitness_center,
                      ),
                      label: Text(
                        active != null ? 'Resume workout' : 'Start workout',
                      ),
                    ),
                    gap,
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _Tile(
                                    'Food',
                                    'Meals & targets',
                                    Icons.restaurant,
                                    accent: true,
                                    () => _push(context, const FoodLogScreen()),
                                  ),
                                ),
                                gap,
                                Expanded(
                                  child: _Tile(
                                    'Workout',
                                    'Presets & sessions',
                                    Icons.fitness_center,
                                    () => _push(context, const WorkoutScreen()),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          gap,
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: _Tile(
                                    'Analyse',
                                    'Trends & exports',
                                    Icons.insights,
                                    () => _push(context, const AnalyseScreen()),
                                  ),
                                ),
                                gap,
                                Expanded(
                                  child: _Tile(
                                    'Profile',
                                    'Settings & backup',
                                    Icons.person_outline,
                                    accent: true,
                                    () => _push(context, const ProfileScreen()),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Hidden until COFFEE_URL is set up (see _openCoffee above).
                    // const SizedBox(height: 8),
                    // TextButton(
                    //   onPressed: () => _openCoffee(context),
                    //   child: const Text('Buy me a coffee'),
                    // ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weekly volume chart with its title and total inside the card.
class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.header, required this.chart, this.total});
  final String header;
  final String? total;
  final Widget chart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(header, style: theme.textTheme.titleMedium)),
              if (total != null)
                Text(
                  total!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Fills the card; at least 150 px when the page has to scroll.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 150),
              child: chart,
            ),
          ),
        ],
      ),
    );
  }
}

/// Home shortcut tile: icon badge at the top, label and subtitle at the bottom.
class _Tile extends StatelessWidget {
  const _Tile(
    this.label,
    this.subtitle,
    this.icon,
    this.onTap, {
    this.accent = false,
  });
  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  /// Aloe badge instead of slate, for a checkerboard of the two accents.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: accent ? scheme.secondary : scheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                icon,
                size: 26,
                color: accent ? scheme.onSecondary : scheme.onPrimary,
              ),
            ),
          ),
          const Spacer(),
          const SizedBox(height: 12),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
