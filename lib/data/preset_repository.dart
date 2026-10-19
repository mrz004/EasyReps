import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import 'database.dart';

/// A preset plus the usage numbers needed for ranking.
class PresetSummary {
  const PresetSummary({
    required this.preset,
    required this.exerciseCount,
    required this.recentFinishedCount,
    this.lastStartedAt,
    this.exerciseNames = const [],
  });

  final Preset preset;
  final int exerciseCount;

  /// Finished sessions in the last [RANKING_WINDOW_DAYS] days.
  final int recentFinishedCount;
  final int? lastStartedAt;

  /// Exercise names in preset order (for the card preview).
  final List<String> exerciseNames;
}

/// Separates names in the SQL group_concat (ASCII unit separator).
const String _NAME_SEPARATOR = '\u001f';

/// Ranks presets for the Workout screen (spec section 4).
/// Group A (preferred today) before group B; each by recent use, then most
/// recent start (never used last), then name.
List<PresetSummary> rankPresets(List<PresetSummary> presets, DateTime now) {
  final weekday = now.weekday;
  int compare(PresetSummary a, PresetSummary b) {
    final byCount = b.recentFinishedCount.compareTo(a.recentFinishedCount);
    if (byCount != 0) return byCount;
    final aLast = a.lastStartedAt, bLast = b.lastStartedAt;
    if (aLast != bLast) {
      if (aLast == null) return 1;
      if (bLast == null) return -1;
      return bLast.compareTo(aLast);
    }
    return a.preset.name.toLowerCase().compareTo(b.preset.name.toLowerCase());
  }

  final groupA =
      presets
          .where((p) => maskHasWeekday(p.preset.preferredDays, weekday))
          .toList()
        ..sort(compare);
  final groupB =
      presets
          .where((p) => !maskHasWeekday(p.preset.preferredDays, weekday))
          .toList()
        ..sort(compare);
  return [...groupA, ...groupB];
}

class PresetRepository {
  PresetRepository(this.db);
  final AppDatabase db;

  Stream<List<PresetSummary>> watchSummaries({DateTime Function()? clock}) {
    final cutoff = (clock ?? DateTime.now)()
        .subtract(const Duration(days: RANKING_WINDOW_DAYS))
        .millisecondsSinceEpoch;
    return db
        .customSelect(
          'SELECT p.*, '
          '(SELECT COUNT(*) FROM preset_exercises pe WHERE pe.preset_id = p.id) AS exercise_count, '
          '(SELECT COUNT(*) FROM sessions s WHERE s.preset_id = p.id '
          '  AND s.ended_at IS NOT NULL AND s.started_at >= ?) AS recent_count, '
          '(SELECT MAX(s.started_at) FROM sessions s WHERE s.preset_id = p.id) AS last_started_at, '
          '(SELECT group_concat(name, char(31)) FROM (SELECT e.name AS name FROM preset_exercises pe '
          '  JOIN exercises e ON e.id = pe.exercise_id WHERE pe.preset_id = p.id ORDER BY pe.position)) '
          '  AS exercise_names '
          'FROM presets p',
          variables: [Variable.withInt(cutoff)],
          readsFrom: {
            db.presets,
            db.presetExercises,
            db.sessions,
            db.exercises,
          },
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              PresetSummary(
                preset: db.presets.map(row.data),
                exerciseCount: row.read<int>('exercise_count'),
                recentFinishedCount: row.read<int>('recent_count'),
                lastStartedAt: row.readNullable<int>('last_started_at'),
                exerciseNames:
                    row
                        .readNullable<String>('exercise_names')
                        ?.split(_NAME_SEPARATOR) ??
                    const [],
              ),
          ],
        );
  }

  Future<Preset?> byId(int id) =>
      (db.select(db.presets)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<List<Exercise>> exercisesOf(int presetId) {
    final query =
        db.select(db.presetExercises).join([
            innerJoin(
              db.exercises,
              db.exercises.id.equalsExp(db.presetExercises.exerciseId),
            ),
          ])
          ..where(db.presetExercises.presetId.equals(presetId))
          ..orderBy([OrderingTerm.asc(db.presetExercises.position)]);
    return query.map((r) => r.readTable(db.exercises)).get();
  }

  /// Creates ([id] null) or updates a preset and replaces its exercise list.
  Future<int> save({
    int? id,
    required String name,
    required int preferredDays,
    required List<String> exerciseIds,
    DateTime? now,
  }) {
    return db.transaction(() async {
      final presetId =
          id ??
          await db
              .into(db.presets)
              .insert(
                PresetsCompanion.insert(
                  name: name.trim(),
                  preferredDays: Value(preferredDays),
                  createdAt: (now ?? DateTime.now()).millisecondsSinceEpoch,
                ),
              );
      if (id != null) {
        await (db.update(db.presets)..where((p) => p.id.equals(id))).write(
          PresetsCompanion(
            name: Value(name.trim()),
            preferredDays: Value(preferredDays),
          ),
        );
        await (db.delete(
          db.presetExercises,
        )..where((pe) => pe.presetId.equals(id))).go();
      }
      final unique = exerciseIds.toSet().toList();
      await db.batch((b) {
        b.insertAll(db.presetExercises, [
          for (var i = 0; i < unique.length; i++)
            PresetExercisesCompanion.insert(
              presetId: presetId,
              exerciseId: unique[i],
              position: i,
            ),
        ]);
      });
      return presetId;
    });
  }

  /// Past sessions keep their snapshot name; their preset_id becomes NULL.
  Future<void> delete(int id) =>
      (db.delete(db.presets)..where((p) => p.id.equals(id))).go();
}
