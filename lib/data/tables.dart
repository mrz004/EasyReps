import 'package:drift/drift.dart';

// Schema mirrors section 3 of the spec. Timestamps are UTC epoch ms; weights kg.

class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get primaryMuscle => text()();
  TextColumn get secondaryMuscles => text().nullable()();
  TextColumn get equipment => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get imageAsset => text().nullable()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Presets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get preferredDays => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
}

class PresetExercises extends Table {
  IntColumn get presetId =>
      integer().references(Presets, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {presetId, exerciseId};
}

@TableIndex(name: 'sessions_started_at', columns: {#startedAt})
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get presetId => integer().nullable().references(
    Presets,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get presetName => text()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
}

class SessionExercises extends Table {
  IntColumn get sessionId =>
      integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get position => integer()();

  @override
  Set<Column> get primaryKey => {sessionId, exerciseId};
}

@DataClassName('WorkoutSet')
@TableIndex(name: 'sets_session', columns: {#sessionId})
@TableIndex(name: 'sets_exercise_logged', columns: {#exerciseId, #loggedAt})
@TableIndex(name: 'sets_logged_at', columns: {#loggedAt})
class Sets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  RealColumn get weightKg => real()();
  IntColumn get reps => integer()();
  IntColumn get loggedAt => integer()();
}

class Foods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get source => text()(); // 'off' | 'custom'
  TextColumn get sourceId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  RealColumn get servingG => real().nullable()();
  // Per 100 g.
  RealColumn get kcal => real()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get sugarG => real().nullable()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get satFatG => real().nullable()();
  RealColumn get sodiumMg => real().nullable()();
  IntColumn get lastUsedAt => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {source, sourceId},
  ];
}

@DataClassName('FoodEntry')
@TableIndex(name: 'food_entries_eaten_at', columns: {#eatenAt})
class FoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get eatenAt => integer()();
  TextColumn get name => text()();
  IntColumn get foodId => integer().nullable().references(
    Foods,
    #id,
    onDelete: KeyAction.setNull,
  )();
  RealColumn get quantityG => real().nullable()();
  // Amounts actually eaten.
  RealColumn get kcal => real()();
  RealColumn get proteinG => real().nullable()();
  RealColumn get carbsG => real().nullable()();
  RealColumn get sugarG => real().nullable()();
  RealColumn get fiberG => real().nullable()();
  RealColumn get fatG => real().nullable()();
  RealColumn get satFatG => real().nullable()();
  RealColumn get sodiumMg => real().nullable()();
}

class NutritionTargets extends Table {
  TextColumn get nutrient => text()();
  RealColumn get value => real()();
  TextColumn get kind => text()(); // 'min' | 'max'

  @override
  Set<Column> get primaryKey => {nutrient};
}

class BodyWeights extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get measuredOn => text().unique()(); // YYYY-MM-DD
  RealColumn get weightKg => real()();
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
