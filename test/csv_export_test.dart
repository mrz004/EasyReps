import 'package:cms/data/database.dart';
import 'package:cms/data/food_repository.dart';
import 'package:cms/data/session_repository.dart';
import 'package:cms/data/stats_repository.dart';
import 'package:cms/features/export/csv_export.dart';
import 'package:cms/features/export/export_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDb());
  tearDown(() => db.close());

  test('workouts.csv: header, one row per set, set numbers, real names', () async {
    await addExercise(db, 'Barbell_Bench_Press');
    await addExercise(db, 'Squat', muscle: 'quadriceps');
    final sessions = SessionRepository(db);
    final id = await sessions.start(null, now: DateTime(2026, 10, 5, 7));
    Future<void> log(String ex, double kg, int reps, int minute) => sessions.logSet(
      sessionId: id, exerciseId: ex, weightKg: kg, reps: reps,
      now: DateTime(2026, 10, 5, 7, minute),
    );
    await log('Barbell_Bench_Press', 60, 8, 1);
    await log('Squat', 100, 5, 2);
    await log('Barbell_Bench_Press', 62.5, 6, 3);
    await sessions.end(id, now: DateTime(2026, 10, 5, 8));

    final rows = await ExportData(db).workoutRows(
      DayRange(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
    );
    final lines = workoutsCsv(rows).trim().split('\r\n');
    expect(lines, [
      'date,time,session,exercise,target_muscle,set_number,weight_kg,reps',
      '2026-10-05,07:01,Mix,Barbell Bench Press,chest,1,60,8',
      '2026-10-05,07:02,Mix,Squat,quadriceps,1,100,5',
      '2026-10-05,07:03,Mix,Barbell Bench Press,chest,2,62.5,6',
    ]);

    final outside = await ExportData(db).workoutRows(
      DayRange(DateTime(2026, 10, 6), DateTime(2026, 10, 31)),
    );
    expect(outside, isEmpty);
  });

  test('food.csv: blanks for unknown values and quoting of commas', () async {
    final foods = FoodRepository(db);
    await foods.addEntry(
      const NutrientValues(kcal: 540, proteinG: 18.25, fatG: 12, satFatG: 3)
          .toEntry(name: 'Rice, dal', eatenAt: DateTime(2026, 10, 5, 13), quantityG: 350),
    );
    await foods.addEntry(
      const NutrientValues(kcal: 180).toEntry(name: 'Quick add', eatenAt: DateTime(2026, 10, 5, 16, 30)),
    );
    final entries = await ExportData(db).foodEntries(DayRange.all(now: DateTime(2026, 10, 18)));
    final lines = foodCsv(entries).trim().split('\r\n');
    expect(lines, [
      'date,time,food,quantity_g,kcal,protein_g,carbs_g,sugar_g,fiber_g,fat_g,saturated_fat_g,sodium_mg',
      '2026-10-05,13:00,"Rice, dal",350,540,18.25,,,,12,3,',
      '2026-10-05,16:30,Quick add,,180,,,,,,,',
    ]);
  });

  test('csvNumber trims float noise', () {
    expect(csvNumber(61.23456789, decimals: 3), '61.235');
    expect(csvNumber(60.0), '60');
    expect(csvNumber(null), '');
  });
}
