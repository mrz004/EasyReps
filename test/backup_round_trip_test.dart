import 'package:cms/core/constants.dart';
import 'package:cms/core/nutrients.dart';
import 'package:cms/data/backup_codec.dart';
import 'package:cms/data/database.dart';
import 'package:cms/data/exercise_repository.dart';
import 'package:cms/data/food_repository.dart';
import 'package:cms/data/preset_repository.dart';
import 'package:cms/data/profile_repository.dart';
import 'package:cms/data/session_repository.dart';
import 'package:drift/drift.dart' show TableInfo, Value;
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

Map<String, dynamic> withoutTimestamp(Map<String, dynamic> payload) =>
    Map.of(payload)..remove('exported_at');

void main() {
  late AppDatabase db;
  late BackupCodec codec;

  setUp(() async {
    db = openTestDb();
    codec = BackupCodec(db);
    await addExercise(db, 'Squat', muscle: 'quadriceps');
    await addExercise(db, 'Bench_Press');
  });
  tearDown(() => db.close());

  Future<void> seedUserData() async {
    final custom = await ExerciseRepository(db).createCustom(
      name: 'Sled push', primaryMuscle: 'quadriceps', description: 'Push it.',
    );
    final presetId = await PresetRepository(db).save(
      name: 'Legs', preferredDays: 1 | 8, exerciseIds: ['Squat', custom.id],
    );
    final sessions = SessionRepository(db);
    final id = await sessions.start(presetId, now: DateTime(2026, 10, 1, 7));
    await sessions.logSet(sessionId: id, exerciseId: 'Squat', weightKg: 100, reps: 5, now: DateTime(2026, 10, 1, 7, 5));
    await sessions.logSet(sessionId: id, exerciseId: custom.id, weightKg: 0, reps: 12, now: DateTime(2026, 10, 1, 7, 9));
    await sessions.end(id, now: DateTime(2026, 10, 1, 8));

    final foods = FoodRepository(db);
    final customFood = await foods.createCustomFood(
      name: 'Protein shake', per100g: const NutrientValues(kcal: 60, proteinG: 10),
    );
    final cached = await foods.cacheOffFoods([
      FoodsCompanion.insert(source: 'off', sourceId: const Value('123'), name: 'Banana', kcal: 89),
    ]);
    await foods.addEntry(const NutrientValues(kcal: 180, proteinG: 30)
        .toEntry(name: 'Protein shake', eatenAt: DateTime(2026, 10, 1, 16), foodId: customFood.id, quantityG: 300));
    await foods.addEntry(const NutrientValues(kcal: 105)
        .toEntry(name: 'Banana', eatenAt: DateTime(2026, 10, 1, 17), foodId: cached.single.id, quantityG: 118));

    final profile = ProfileRepository(db);
    await profile.setTarget(Nutrient.proteinG, 140, TargetKind.min);
    await profile.saveBodyWeight(DateTime(2026, 10, 1), 70.4);
    await profile.setSetting(SETTING_WEIGHT_UNIT, 'lb');
    await profile.setSetting(SETTING_HEIGHT_CM, '172');
  }

  test('empty database produces an empty backup (never uploaded)', () async {
    final payload = await codec.export();
    expect(BackupCodec.isEmpty(payload), isTrue);
    expect(payload['schema_version'], BACKUP_SCHEMA_VERSION);
  });

  test('export -> wipe -> restore round trip', () async {
    await seedUserData();
    final before = await codec.export();
    expect(BackupCodec.isEmpty(before), isFalse);
    expect(before['exercises'], hasLength(1), reason: 'seeded exercises are excluded');
    expect(before['foods'], hasLength(1), reason: 'Open Food Facts cache is excluded');

    // Wipe everything the user owns, plus some unrelated local state.
    await db.transaction(() async {
      for (final t in <TableInfo>[db.sets, db.sessionExercises, db.sessions, db.presetExercises,
          db.presets, db.foodEntries, db.foods, db.nutritionTargets, db.bodyWeights]) {
        await db.delete(t).go();
      }
      await (db.delete(db.exercises)..where((e) => e.isCustom.equals(true))).go();
      await db.delete(db.settings).go();
    });
    expect(BackupCodec.isEmpty(await codec.export()), isTrue);

    await codec.restore(before);
    final after = await codec.export();

    // The cached food is gone, so its entry's food_id becomes NULL.
    final entries = (before['food_entries'] as List).cast<Map<String, dynamic>>();
    final expectedEntries = [
      for (final e in entries) e['name'] == 'Banana' ? (Map.of(e)..['foodId'] = null) : e,
    ];
    expect(after['food_entries'], expectedEntries);
    expect(
      withoutTimestamp(after)..remove('food_entries'),
      withoutTimestamp(before)..remove('food_entries'),
    );
    expect(await ProfileRepository(db).getSetting(SETTING_WEIGHT_UNIT), 'lb');
  });

  test('restore keeps sets whose exercise is missing locally', () async {
    await seedUserData();
    final payload = await codec.export();
    final other = openTestDb(); // No seeded exercises at all.
    addTearDown(other.close);
    await BackupCodec(other).restore(payload);
    expect(await other.select(other.sets).get(), hasLength(2));
    final squat = await (other.select(other.exercises)..where((e) => e.id.equals('Squat'))).getSingle();
    expect(squat.isCustom, isTrue);
  });

  test('a failed restore leaves local data untouched', () async {
    await seedUserData();
    final before = await codec.export();
    final broken = Map<String, dynamic>.of(before)
      ..['sets'] = [
        {'id': 999, 'sessionId': 424242, 'exerciseId': 'Squat', 'weightKg': 1.0, 'reps': 1, 'loggedAt': 0},
      ];
    await expectLater(codec.restore(broken), throwsA(anything));
    expect(withoutTimestamp(await codec.export()), withoutTimestamp(before));
  });

  test('unsupported schema versions are rejected', () async {
    expect(() => codec.restore({'schema_version': BACKUP_SCHEMA_VERSION + 1}), throwsFormatException);
  });
}
