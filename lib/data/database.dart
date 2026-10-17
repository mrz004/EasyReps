import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

const String DATABASE_NAME = 'count_my_sweat';

@DriftDatabase(
  tables: [
    Exercises,
    Presets,
    PresetExercises,
    Sessions,
    SessionExercises,
    Sets,
    Foods,
    FoodEntries,
    NutritionTargets,
    BodyWeights,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// The workmanager backup runs in another engine of the same process.
  /// Sharing one drift server keeps writes serialised and lets the UI see the
  /// settings that background backups write.
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: DATABASE_NAME,
              native: const DriftNativeOptions(shareAcrossIsolates: true),
            ),
      );

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createActiveSessionGuard();
    },
    onUpgrade: (m, from, to) async {
      // Add a step per version bump, e.g. `if (from < 2) await m.addColumn(...)`.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Enforces "at most ONE active session" at the database level.
  Future<void> _createActiveSessionGuard() => customStatement(
    'CREATE UNIQUE INDEX IF NOT EXISTS sessions_one_active '
    'ON sessions ((ended_at IS NULL)) WHERE ended_at IS NULL',
  );

  /// Tables holding user data (everything except settings).
  List<TableInfo> get userDataTables => [
    exercises,
    presets,
    presetExercises,
    sessions,
    sessionExercises,
    sets,
    foods,
    foodEntries,
    nutritionTargets,
    bodyWeights,
  ];
}
