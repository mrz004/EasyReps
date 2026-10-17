import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import '../core/nutrients.dart';
import '../core/units.dart';
import 'database.dart';

class Target {
  const Target(this.nutrient, this.value, this.kind);
  final Nutrient nutrient;
  final double value;
  final TargetKind kind;
}

/// Settings, nutrition targets and body weights.
class ProfileRepository {
  ProfileRepository(this.db);
  final AppDatabase db;

  // Settings ---------------------------------------------------------------

  Future<String?> getSetting(String key) async => (await (db.select(
    db.settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchSetting(String key) =>
      (db.select(db.settings)..where((s) => s.key.equals(key)))
          .watchSingleOrNull()
          .map((r) => r?.value);

  Future<void> setSetting(String key, String? value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: Value(value)));

  Stream<WeightUnit> watchWeightUnit() =>
      watchSetting(SETTING_WEIGHT_UNIT).map(WeightUnit.fromKey);

  Future<void> setWeightUnit(WeightUnit unit) =>
      setSetting(SETTING_WEIGHT_UNIT, unit.name);

  Stream<double?> watchHeightCm() => watchSetting(
    SETTING_HEIGHT_CM,
  ).map((v) => v == null ? null : double.tryParse(v));

  Future<void> setHeightCm(double? cm) =>
      setSetting(SETTING_HEIGHT_CM, cm?.toString());

  // Targets ----------------------------------------------------------------

  Stream<Map<Nutrient, Target>> watchTargets() =>
      db.select(db.nutritionTargets).watch().map((rows) {
        final targets = <Nutrient, Target>{};
        for (final r in rows) {
          final n = Nutrient.fromKey(r.nutrient);
          if (n != null) targets[n] = Target(n, r.value, TargetKind.fromKey(r.kind));
        }
        return targets;
      });

  Future<Map<Nutrient, Target>> getTargets() => watchTargets().first;

  Future<void> setTarget(Nutrient nutrient, double value, TargetKind kind) {
    if (value.isNaN || value < 0) throw ArgumentError('Invalid target');
    return db.into(db.nutritionTargets).insertOnConflictUpdate(
      NutritionTargetsCompanion.insert(
        nutrient: nutrient.key,
        value: value,
        kind: kind.key,
      ),
    );
  }

  Future<void> removeTarget(Nutrient nutrient) => (db.delete(
    db.nutritionTargets,
  )..where((t) => t.nutrient.equals(nutrient.key))).go();

  // Body weights -------------------------------------------------------------

  /// Newest first.
  Stream<List<BodyWeight>> watchBodyWeights() => (db.select(db.bodyWeights)
        ..orderBy([(b) => OrderingTerm.desc(b.measuredOn)]))
      .watch();

  /// Saving the same day replaces the previous value.
  Future<void> saveBodyWeight(DateTime day, double weightKg) {
    if (weightKg.isNaN || weightKg <= 0) throw ArgumentError('Invalid weight');
    final row = BodyWeightsCompanion.insert(
      measuredOn: dayKey(day),
      weightKg: weightKg,
    );
    return db.into(db.bodyWeights).insert(
      row,
      onConflict: DoUpdate((_) => row, target: [db.bodyWeights.measuredOn]),
    );
  }

  Future<void> deleteBodyWeight(int id) =>
      (db.delete(db.bodyWeights)..where((b) => b.id.equals(id))).go();
}
