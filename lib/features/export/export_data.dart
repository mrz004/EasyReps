import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../data/stats_repository.dart';

/// One logged set with the names needed for exports.
class WorkoutExportRow {
  const WorkoutExportRow({
    required this.loggedAt,
    required this.sessionId,
    required this.sessionName,
    required this.exerciseId,
    required this.exerciseName,
    required this.targetMuscle,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
  });

  final DateTime loggedAt;
  final int sessionId;
  final String sessionName;
  final String exerciseId;
  final String exerciseName;
  final String targetMuscle;

  /// Order of the set within that exercise in that session (1-based).
  final int setNumber;
  final double weightKg;
  final int reps;
}

/// Reads raw rows for exports. Only rows inside the range are returned.
class ExportData {
  ExportData(this.db);
  final AppDatabase db;

  Future<List<WorkoutExportRow>> workoutRows(DayRange range) async {
    final from = range.fromMs ?? 0;
    final rows = await db.customSelect(
      'SELECT s.id, s.session_id, s.exercise_id, s.weight_kg, s.reps, s.logged_at, '
      '  ss.preset_name, e.name AS exercise_name, e.primary_muscle, '
      '  (SELECT COUNT(*) FROM sets s2 WHERE s2.session_id = s.session_id '
      '     AND s2.exercise_id = s.exercise_id '
      '     AND (s2.logged_at < s.logged_at OR (s2.logged_at = s.logged_at AND s2.id <= s.id))) AS set_number '
      'FROM sets s '
      'JOIN sessions ss ON ss.id = s.session_id '
      'JOIN exercises e ON e.id = s.exercise_id '
      'WHERE s.logged_at >= ? AND s.logged_at < ? '
      'ORDER BY s.logged_at, s.id',
      variables: [Variable.withInt(from), Variable.withInt(range.toMsExclusive)],
      readsFrom: {db.sets, db.sessions, db.exercises},
    ).get();
    return [
      for (final r in rows)
        WorkoutExportRow(
          loggedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('logged_at')),
          sessionId: r.read<int>('session_id'),
          sessionName: r.read<String>('preset_name'),
          exerciseId: r.read<String>('exercise_id'),
          exerciseName: r.read<String>('exercise_name'),
          targetMuscle: r.read<String>('primary_muscle'),
          setNumber: r.read<int>('set_number'),
          weightKg: r.read<double>('weight_kg'),
          reps: r.read<int>('reps'),
        ),
    ];
  }

  /// Heaviest weight per exercise logged before [beforeMs].
  Future<Map<String, double>> maxWeightBefore(int beforeMs) async {
    final maxWeight = db.sets.weightKg.max();
    final rows = await (db.selectOnly(db.sets)
          ..addColumns([db.sets.exerciseId, maxWeight])
          ..where(db.sets.loggedAt.isSmallerThanValue(beforeMs))
          ..groupBy([db.sets.exerciseId]))
        .get();
    return {for (final r in rows) r.read(db.sets.exerciseId)!: r.read(maxWeight)!};
  }

  Future<List<FoodEntry>> foodEntries(DayRange range) {
    final from = range.fromMs ?? 0;
    return (db.select(db.foodEntries)
          ..where(
            (e) =>
                e.eatenAt.isBiggerOrEqualValue(from) &
                e.eatenAt.isSmallerThanValue(range.toMsExclusive),
          )
          ..orderBy([(e) => OrderingTerm.asc(e.eatenAt), (e) => OrderingTerm.asc(e.id)]))
        .get();
  }
}
