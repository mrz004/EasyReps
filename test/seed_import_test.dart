import 'dart:convert';
import 'dart:io';

import 'package:cms/core/constants.dart';
import 'package:cms/data/exercise_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  final asset = File(EXERCISES_JSON_ASSET);

  test('bundled dataset imports once and never touches custom exercises', () async {
    final db = openTestDb();
    addTearDown(db.close);
    final raw = await asset.readAsString();
    final expected = (jsonDecode(raw) as List).length;

    final custom = await ExerciseRepository(db).createCustom(name: 'Sled push', primaryMuscle: 'quadriceps');
    final seeder = ExerciseSeeder(db);
    expect(await seeder.seedIfNeeded(() async => raw), expected);
    expect(await seeder.seedIfNeeded(() async => raw), 0, reason: 'second launch skips the import');

    final all = await db.select(db.exercises).get();
    expect(all.where((e) => !e.isCustom), hasLength(expected));
    expect(all.singleWhere((e) => e.isCustom).id, custom.id);

    final bench = all.singleWhere((e) => e.id == 'Barbell_Bench_Press_-_Medium_Grip');
    expect(bench.primaryMuscle, 'chest');
    expect(bench.description, isNotEmpty);
    expect(bench.imageAsset, 'assets/exercises/img/Barbell_Bench_Press_-_Medium_Grip.webp');
    expect(File(bench.imageAsset!).existsSync(), isTrue);

    // Every image path the seeder stores points at a bundled file.
    for (final e in all.where((e) => e.imageAsset != null)) {
      expect(File(e.imageAsset!).existsSync(), isTrue, reason: e.id);
    }
  }, skip: asset.existsSync() ? false : 'run tools/prepare_exercises.py first');

  test('a missing dataset leaves the app bootable', () async {
    final db = openTestDb();
    addTearDown(db.close);
    expect(await ExerciseSeeder(db).seedIfNeeded(() => Future.error('missing')), 0);
  });
}
