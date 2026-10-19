import 'package:flutter/material.dart';

import '../../core/nutrients.dart';
import '../../data/profile_repository.dart';

/// True when any "at most" target is exceeded by [totals].
bool anyLimitExceeded(Map<Nutrient, double> totals, Map<Nutrient, Target> targets) =>
    targets.values.any(
      (t) => targetStatus(totals[t.nutrient]!, t.value, t.kind) == TargetStatus.exceeded,
    );

/// Headline nutrients with optional target bars, plus an expandable breakdown.
class NutritionCard extends StatefulWidget {
  const NutritionCard({super.key, required this.totals, required this.targets});
  final Map<Nutrient, double> totals;
  final Map<Nutrient, Target> targets;

  @override
  State<NutritionCard> createState() => _NutritionCardState();
}

class _NutritionCardState extends State<NutritionCard> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final totals = widget.totals;
    final nonSat = nonSaturatedFat(totals[Nutrient.fatG], totals[Nutrient.satFatG]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (final n in Nutrient.HEADLINE) _row(n),
                if (_details) ...[
                  const Divider(height: 24),
                  for (final n in Nutrient.DETAILS) ...[
                    _row(n),
                    if (n == Nutrient.satFatG && nonSat != null)
                      _plainRow('Non-saturated fat', '${Nutrient.fatG.format(nonSat)} g'),
                  ],
                ],
              ],
            ),
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _details = !_details),
            icon: Icon(_details ? Icons.expand_less : Icons.expand_more),
            label: Text(_details ? 'Hide details' : 'Show details'),
          ),
        ),
      ],
    );
  }

  Widget _plainRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
        Text(value),
      ],
    ),
  );

  Widget _row(Nutrient n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = widget.totals[n]!;
    final target = widget.targets[n];
    if (target == null) return _plainRow(n.label, n.formatWithUnit(total));

    final status = targetStatus(total, target.value, target.kind);
    final progress = target.value <= 0 ? 1.0 : (total / target.value).clamp(0.0, 1.0);
    final color = switch (status) {
      TargetStatus.exceeded => scheme.error,
      TargetStatus.met => scheme.secondary,
      _ => scheme.primary,
    };
    final suffix = switch (status) {
      TargetStatus.met => '  met',
      TargetStatus.exceeded => '  over',
      _ => '',
    };
    final unit = n == Nutrient.kcal ? '' : ' ${n.unit}';
    return Semantics(
      label: '${n.label}: ${n.format(total)} of ${target.kind.label} '
          '${n.format(target.value)}$unit${suffix.isEmpty ? '' : ',${suffix.trim()}'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(n.label, style: theme.textTheme.labelLarge)),
                if (status == TargetStatus.met)
                  Icon(Icons.check_circle, size: 16, color: color),
                if (status == TargetStatus.exceeded)
                  Icon(Icons.error_outline, size: 16, color: color),
                Text(
                  ' ${n.format(total)} / ${n.format(target.value)}$unit',
                  style: TextStyle(color: status == TargetStatus.exceeded ? color : null),
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress,
              color: color,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}
