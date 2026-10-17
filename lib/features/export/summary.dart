import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../data/database.dart';
import '../../data/food_repository.dart';
import '../../data/profile_repository.dart';
import 'export_data.dart';

class PersonalRecord {
  const PersonalRecord(this.exerciseName, this.weightKg, this.date);
  final String exerciseName;
  final double weightKg;
  final DateTime date;
}

class WorkoutSummary {
  const WorkoutSummary({
    required this.sessionCount,
    required this.totalVolumeKg,
    required this.firstHalfVolumeKg,
    required this.secondHalfVolumeKg,
    required this.records,
  });

  final int sessionCount;
  final double totalVolumeKg;
  final double firstHalfVolumeKg;
  final double secondHalfVolumeKg;
  final List<PersonalRecord> records;

  /// Percent change from the first to the second half; null if the first is 0.
  double? get trendPercent => firstHalfVolumeKg == 0
      ? null
      : (secondHalfVolumeKg - firstHalfVolumeKg) / firstHalfVolumeKg * 100;
}

/// [earlierMax]: heaviest weight per exercise before the period. An exercise
/// is a record only if it beats existing earlier history.
WorkoutSummary summariseWorkouts(
  List<WorkoutExportRow> rows,
  Map<String, double> earlierMax,
  DateTime firstDay,
  DateTime lastDay,
) {
  final midMs = _midpointMs(firstDay, lastDay);
  var total = 0.0, firstHalf = 0.0, secondHalf = 0.0;
  final best = <String, WorkoutExportRow>{};
  for (final r in rows) {
    final volume = r.weightKg * r.reps;
    total += volume;
    r.loggedAt.millisecondsSinceEpoch < midMs ? firstHalf += volume : secondHalf += volume;
    final current = best[r.exerciseId];
    if (current == null || r.weightKg > current.weightKg) best[r.exerciseId] = r;
  }
  final records = [
    for (final r in best.values)
      if (earlierMax[r.exerciseId] case final previous? when r.weightKg > previous)
        PersonalRecord(r.exerciseName, r.weightKg, r.loggedAt),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return WorkoutSummary(
    sessionCount: {for (final r in rows) r.sessionId}.length,
    totalVolumeKg: total,
    firstHalfVolumeKg: firstHalf,
    secondHalfVolumeKg: secondHalf,
    records: records,
  );
}

int _midpointMs(DateTime firstDay, DateTime lastDay) {
  final start = startOfDay(firstDay).millisecondsSinceEpoch;
  final end = addDays(startOfDay(lastDay), 1).millisecondsSinceEpoch;
  return start + (end - start) ~/ 2;
}

class TargetResult {
  const TargetResult(this.target, this.daysOk);
  final Target target;

  /// Logged days on which the target was met ("at least") or kept ("at most").
  final int daysOk;
}

class FoodSummary {
  const FoodSummary({required this.loggedDays, required this.averages, required this.targets});

  /// Days with at least one entry; averages are over these days.
  final int loggedDays;
  final Map<Nutrient, double> averages;
  final List<TargetResult> targets;
}

FoodSummary summariseFood(List<FoodEntry> entries, Map<Nutrient, Target> targets) {
  final byDay = <DateTime, List<FoodEntry>>{};
  for (final e in entries) {
    byDay.putIfAbsent(startOfDay(fromMillis(e.eatenAt)), () => []).add(e);
  }
  final dayTotals = [for (final day in byDay.values) sumNutrients(day)];
  final days = dayTotals.length;
  return FoodSummary(
    loggedDays: days,
    averages: {
      for (final n in Nutrient.values)
        n: days == 0 ? 0 : dayTotals.fold<double>(0, (s, t) => s + t[n]!) / days,
    },
    targets: [
      for (final t in targets.values)
        TargetResult(
          t,
          dayTotals.where((totals) {
            final status = targetStatus(totals[t.nutrient]!, t.value, t.kind);
            return status == TargetStatus.met || status == TargetStatus.kept;
          }).length,
        ),
    ],
  );
}
