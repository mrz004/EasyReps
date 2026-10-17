import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../core/constants.dart';
import 'database.dart';

class ExerciseRepository {
  ExerciseRepository(this.db);
  final AppDatabase db;

  Stream<List<Exercise>> watchAll() => (db.select(db.exercises)
        ..orderBy([(e) => OrderingTerm.asc(e.name.lower())]))
      .watch();

  Future<Exercise?> byId(String id) =>
      (db.select(db.exercises)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  Stream<Exercise?> watchById(String id) =>
      (db.select(db.exercises)..where((e) => e.id.equals(id)))
          .watchSingleOrNull();

  Future<List<Exercise>> byIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await (db.select(
      db.exercises,
    )..where((e) => e.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    return [for (final id in ids) ?byId[id]];
  }

  /// Distinct primary muscles, alphabetical.
  Future<List<String>> primaryMuscles() async {
    final query = db.selectOnly(db.exercises, distinct: true)
      ..addColumns([db.exercises.primaryMuscle])
      ..orderBy([OrderingTerm.asc(db.exercises.primaryMuscle)]);
    final rows = await query.get();
    return [for (final r in rows) r.read(db.exercises.primaryMuscle)!];
  }

  Future<Exercise> createCustom({
    required String name,
    required String primaryMuscle,
    String? description,
  }) async {
    final trimmedDescription = description?.trim();
    final row = ExercisesCompanion.insert(
      id: 'custom-${newUuid()}',
      name: name.trim(),
      primaryMuscle: primaryMuscle,
      description: Value(
        trimmedDescription == null || trimmedDescription.isEmpty
            ? null
            : trimmedDescription,
      ),
      isCustom: const Value(true),
    );
    return db.into(db.exercises).insertReturning(row);
  }
}

/// Random RFC 4122 version 4 UUID.
String newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Builds the short description from the first one or two instruction steps.
String? buildDescription(List<String> instructions) {
  final steps = instructions.map((s) => s.trim()).where((s) => s.isNotEmpty);
  if (steps.isEmpty) return null;
  return steps.take(2).join(' ');
}

/// Imports the bundled free-exercise-db dataset into `exercises`.
class ExerciseSeeder {
  ExerciseSeeder(this.db);
  final AppDatabase db;

  /// Imports when the bundled dataset size differs from the last import.
  /// Seeded rows are upserted; custom exercises ("custom-" ids) are never touched.
  Future<int> seedIfNeeded(Future<String> Function() loadJson) async {
    String raw;
    try {
      raw = await loadJson();
    } on Object {
      return 0; // Dataset not bundled yet (see tools/prepare_exercises.py).
    }
    final items = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final countKey = '${items.length}';
    final previous = await (db.select(
      db.settings,
    )..where((s) => s.key.equals(SETTING_SEED_COUNT))).getSingleOrNull();
    if (previous?.value == countKey) return 0;

    final rows = [for (final item in items) _toCompanion(item)];
    await db.transaction(() async {
      await db.batch((b) {
        b.insertAllOnConflictUpdate(db.exercises, rows);
        b.insert(
          db.settings,
          SettingsCompanion.insert(key: SETTING_SEED_COUNT, value: Value(countKey)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
    return rows.length;
  }

  ExercisesCompanion _toCompanion(Map<String, dynamic> item) {
    final id = item['id'] as String;
    final secondary = (item['secondary_muscles'] as List?)?.cast<String>() ?? [];
    final instructions = (item['instructions'] as List?)?.cast<String>() ?? [];
    return ExercisesCompanion.insert(
      id: id,
      name: item['name'] as String,
      primaryMuscle: item['primary_muscle'] as String? ?? 'other',
      secondaryMuscles: Value(secondary.isEmpty ? null : secondary.join(',')),
      equipment: Value(item['equipment'] as String?),
      description: Value(buildDescription(instructions)),
      imageAsset: Value(
        item['has_image'] == false ? null : '$EXERCISE_IMAGE_DIR/$id.webp',
      ),
      isCustom: const Value(false),
    );
  }
}
