import 'package:cms/data/database.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

AppDatabase openTestDb() => AppDatabase(
  DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
);

Future<void> addExercise(AppDatabase db, String id, {String muscle = 'chest'}) =>
    db.into(db.exercises).insert(
      ExercisesCompanion.insert(id: id, name: id.replaceAll('_', ' '), primaryMuscle: muscle),
    );
