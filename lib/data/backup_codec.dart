import 'package:drift/drift.dart';

import '../core/constants.dart';
import 'database.dart';

/// Serialises user data to the backup JSON and restores it (spec section 8).
/// Excludes the Open Food Facts cache and the seeded exercises.
class BackupCodec {
  BackupCodec(this.db);
  final AppDatabase db;

  static const List<String> _SETTINGS_KEYS = [SETTING_WEIGHT_UNIT, SETTING_HEIGHT_CM];

  Future<Map<String, dynamic>> export({DateTime? now}) async {
    return db.transaction(() async {
      List<Map<String, dynamic>> json<T extends DataClass>(List<T> rows) =>
          [for (final r in rows) r.toJson()];

      final settingsRows = await (db.select(
        db.settings,
      )..where((s) => s.key.isIn(_SETTINGS_KEYS))).get();

      return {
        'schema_version': BACKUP_SCHEMA_VERSION,
        'exported_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'exercises': json(
          await (db.select(db.exercises)..where((e) => e.isCustom.equals(true))).get(),
        ),
        'presets': json(await db.select(db.presets).get()),
        'preset_exercises': json(await db.select(db.presetExercises).get()),
        'sessions': json(await db.select(db.sessions).get()),
        'session_exercises': json(await db.select(db.sessionExercises).get()),
        'sets': json(await db.select(db.sets).get()),
        'foods': json(
          await (db.select(db.foods)..where((f) => f.source.equals('custom'))).get(),
        ),
        'food_entries': json(await db.select(db.foodEntries).get()),
        'nutrition_targets': json(await db.select(db.nutritionTargets).get()),
        'body_weights': json(await db.select(db.bodyWeights).get()),
        'settings': {for (final s in settingsRows) s.key: s.value},
      };
    });
  }

  /// True when the payload holds no user data (settings alone do not count).
  static bool isEmpty(Map<String, dynamic> payload) {
    const keys = [
      'exercises', 'presets', 'sessions', 'sets', 'foods',
      'food_entries', 'nutrition_targets', 'body_weights',
    ];
    return keys.every((k) => (payload[k] as List?)?.isEmpty ?? true);
  }

  /// Whether the local database currently holds any user data.
  Future<bool> localIsEmpty() async => isEmpty(await export());

  /// Replaces all local user data with [payload] in one transaction.
  Future<void> restore(Map<String, dynamic> payload) async {
    final version = payload['schema_version'];
    if (version is! int || version > BACKUP_SCHEMA_VERSION) {
      throw const FormatException('Unsupported backup version');
    }
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) fromJson) => [
      for (final m in (payload[key] as List? ?? const []))
        fromJson((m as Map).cast<String, dynamic>()),
    ];

    // Parse everything before touching the database.
    final exercises = rows('exercises', Exercise.fromJson);
    final presets = rows('presets', Preset.fromJson);
    final presetExercises = rows('preset_exercises', PresetExercise.fromJson);
    final sessions = rows('sessions', Session.fromJson);
    final sessionExercises = rows('session_exercises', SessionExercise.fromJson);
    final sets = rows('sets', WorkoutSet.fromJson);
    final foods = rows('foods', Food.fromJson);
    final entries = rows('food_entries', FoodEntry.fromJson);
    final targets = rows('nutrition_targets', NutritionTarget.fromJson);
    final bodyWeights = rows('body_weights', BodyWeight.fromJson);
    final settings = (payload['settings'] as Map?)?.cast<String, dynamic>() ?? {};

    await db.transaction(() async {
      for (final table in <TableInfo>[
        db.sets, db.sessionExercises, db.sessions, db.presetExercises,
        db.presets, db.foodEntries, db.foods, db.nutritionTargets, db.bodyWeights,
      ]) {
        await db.delete(table).go();
      }
      await (db.delete(db.exercises)..where((e) => e.isCustom.equals(true))).go();

      await db.batch((b) => b.insertAll(db.exercises, exercises, mode: InsertMode.insertOrReplace));
      await _ensureExercisesExist({
        for (final r in presetExercises) r.exerciseId,
        for (final r in sessionExercises) r.exerciseId,
        for (final r in sets) r.exerciseId,
      });

      final foodIds = {for (final f in foods) f.id};
      await db.batch((b) {
        b.insertAll(db.presets, presets);
        b.insertAll(db.presetExercises, presetExercises);
        b.insertAll(db.sessions, sessions);
        b.insertAll(db.sessionExercises, sessionExercises);
        b.insertAll(db.sets, sets);
        b.insertAll(db.foods, foods);
        b.insertAll(db.foodEntries, [
          for (final e in entries)
            foodIds.contains(e.foodId) ? e : e.copyWith(foodId: const Value(null)),
        ]);
        b.insertAll(db.nutritionTargets, targets);
        b.insertAll(db.bodyWeights, bodyWeights);
        for (final key in _SETTINGS_KEYS) {
          if (settings.containsKey(key)) {
            b.insert(
              db.settings,
              SettingsCompanion.insert(key: key, value: Value(settings[key]?.toString())),
              mode: InsertMode.insertOrReplace,
            );
          }
        }
      });
    });
  }

  /// Logged sets must never be dropped: an exercise missing from this
  /// install's dataset is recreated as a custom placeholder.
  Future<void> _ensureExercisesExist(Set<String> ids) async {
    if (ids.isEmpty) return;
    final existing = await (db.selectOnly(db.exercises)
          ..addColumns([db.exercises.id])
          ..where(db.exercises.id.isIn(ids)))
        .map((r) => r.read(db.exercises.id)!)
        .get();
    final missing = ids.difference(existing.toSet());
    await db.batch((b) {
      b.insertAll(db.exercises, [
        for (final id in missing)
          ExercisesCompanion.insert(
            id: id,
            name: id.replaceAll('_', ' '),
            primaryMuscle: 'other',
            isCustom: const Value(true),
          ),
      ]);
    });
  }
}
