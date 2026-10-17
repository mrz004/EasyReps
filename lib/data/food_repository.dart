import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import '../core/nutrients.dart';
import 'database.dart';

/// Nutrient amounts of one entry or one food (per 100 g).
class NutrientValues {
  const NutrientValues({
    required this.kcal,
    this.proteinG,
    this.carbsG,
    this.sugarG,
    this.fiberG,
    this.fatG,
    this.satFatG,
    this.sodiumMg,
  });

  factory NutrientValues.ofEntry(FoodEntry e) => NutrientValues(
    kcal: e.kcal,
    proteinG: e.proteinG,
    carbsG: e.carbsG,
    sugarG: e.sugarG,
    fiberG: e.fiberG,
    fatG: e.fatG,
    satFatG: e.satFatG,
    sodiumMg: e.sodiumMg,
  );

  factory NutrientValues.ofFood(Food f) => NutrientValues(
    kcal: f.kcal,
    proteinG: f.proteinG,
    carbsG: f.carbsG,
    sugarG: f.sugarG,
    fiberG: f.fiberG,
    fatG: f.fatG,
    satFatG: f.satFatG,
    sodiumMg: f.sodiumMg,
  );

  final double kcal;
  final double? proteinG, carbsG, sugarG, fiberG, fatG, satFatG, sodiumMg;

  double? operator [](Nutrient n) => switch (n) {
    Nutrient.kcal => kcal,
    Nutrient.proteinG => proteinG,
    Nutrient.carbsG => carbsG,
    Nutrient.sugarG => sugarG,
    Nutrient.fiberG => fiberG,
    Nutrient.fatG => fatG,
    Nutrient.satFatG => satFatG,
    Nutrient.sodiumMg => sodiumMg,
  };

  /// Per-100 g values scaled to [quantityG].
  NutrientValues scaledTo(double quantityG) => scaledBy(quantityG / 100);

  NutrientValues scaledBy(double factor) {
    double? s(double? v) => v == null ? null : v * factor;
    return NutrientValues(
      kcal: kcal * factor,
      proteinG: s(proteinG),
      carbsG: s(carbsG),
      sugarG: s(sugarG),
      fiberG: s(fiberG),
      fatG: s(fatG),
      satFatG: s(satFatG),
      sodiumMg: s(sodiumMg),
    );
  }

  FoodEntriesCompanion toEntry({
    required String name,
    required DateTime eatenAt,
    int? foodId,
    double? quantityG,
  }) => FoodEntriesCompanion.insert(
    eatenAt: eatenAt.millisecondsSinceEpoch,
    name: name.trim(),
    foodId: Value(foodId),
    quantityG: Value(quantityG),
    kcal: kcal,
    proteinG: Value(proteinG),
    carbsG: Value(carbsG),
    sugarG: Value(sugarG),
    fiberG: Value(fiberG),
    fatG: Value(fatG),
    satFatG: Value(satFatG),
    sodiumMg: Value(sodiumMg),
  );
}

/// Sums entries; unknown (null) values count as 0.
Map<Nutrient, double> sumNutrients(Iterable<FoodEntry> entries) {
  final totals = {for (final n in Nutrient.values) n: 0.0};
  for (final e in entries) {
    final v = NutrientValues.ofEntry(e);
    for (final n in Nutrient.values) {
      totals[n] = totals[n]! + (v[n] ?? 0);
    }
  }
  return totals;
}

class FoodRepository {
  FoodRepository(this.db);
  final AppDatabase db;

  Stream<List<FoodEntry>> watchEntriesForDay(DateTime day) {
    final from = startOfDay(day).millisecondsSinceEpoch;
    final to = addDays(startOfDay(day), 1).millisecondsSinceEpoch;
    return (db.select(db.foodEntries)
          ..where((e) => e.eatenAt.isBiggerOrEqualValue(from) & e.eatenAt.isSmallerThanValue(to))
          ..orderBy([(e) => OrderingTerm.asc(e.eatenAt)]))
        .watch();
  }

  Future<int> addEntry(FoodEntriesCompanion entry) async {
    return db.transaction(() async {
      final id = await db.into(db.foodEntries).insert(entry);
      final foodId = entry.foodId.present ? entry.foodId.value : null;
      if (foodId != null) {
        await (db.update(db.foods)..where((f) => f.id.equals(foodId))).write(
          FoodsCompanion(lastUsedAt: Value(DateTime.now().millisecondsSinceEpoch)),
        );
      }
      return id;
    });
  }

  Future<void> updateEntry(int id, FoodEntriesCompanion entry) =>
      (db.update(db.foodEntries)..where((e) => e.id.equals(id))).write(entry);

  Future<void> deleteEntry(int id) =>
      (db.delete(db.foodEntries)..where((e) => e.id.equals(id))).go();

  /// The last [RECENT_FOODS_LIMIT] distinct entries (by name and amount).
  Future<List<FoodEntry>> recentEntries() async {
    final rows = await (db.select(db.foodEntries)
          ..orderBy([(e) => OrderingTerm.desc(e.eatenAt)])
          ..limit(300))
        .get();
    final seen = <String>{};
    final result = <FoodEntry>[];
    for (final e in rows) {
      final key = '${e.name.toLowerCase()}|${e.quantityG}|${e.kcal}';
      if (seen.add(key)) result.add(e);
      if (result.length == RECENT_FOODS_LIMIT) break;
    }
    return result;
  }

  /// Cached and custom foods whose name contains [query].
  Future<List<Food>> searchLocal(String query, {int limit = 30}) {
    final pattern = '%${query.trim().toLowerCase()}%';
    return (db.select(db.foods)
          ..where((f) => f.name.lower().like(pattern) | f.brand.lower().like(pattern))
          ..orderBy([
            (f) => OrderingTerm(expression: f.lastUsedAt, mode: OrderingMode.desc, nulls: NullsOrder.last),
            (f) => OrderingTerm.asc(f.name),
          ])
          ..limit(limit))
        .get();
  }

  /// Upserts Open Food Facts results into the cache and returns stored rows.
  Future<List<Food>> cacheOffFoods(List<FoodsCompanion> foods) {
    return db.transaction(() async {
      final stored = <Food>[];
      for (final food in foods) {
        stored.add(
          await db.into(db.foods).insertReturning(
            food,
            onConflict: DoUpdate(
              (_) => food,
              target: [db.foods.source, db.foods.sourceId],
            ),
          ),
        );
      }
      return stored;
    });
  }

  Future<Food> createCustomFood({
    required String name,
    required NutrientValues per100g,
    double? servingG,
  }) => db.into(db.foods).insertReturning(
    FoodsCompanion.insert(
      source: 'custom',
      name: name.trim(),
      servingG: Value(servingG),
      kcal: per100g.kcal,
      proteinG: Value(per100g.proteinG),
      carbsG: Value(per100g.carbsG),
      sugarG: Value(per100g.sugarG),
      fiberG: Value(per100g.fiberG),
      fatG: Value(per100g.fatG),
      satFatG: Value(per100g.satFatG),
      sodiumMg: Value(per100g.sodiumMg),
    ),
  );
}
