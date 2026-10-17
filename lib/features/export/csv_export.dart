import 'package:csv/csv.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import 'export_data.dart';

const List<String> WORKOUT_CSV_HEADER = [
  'date', 'time', 'session', 'exercise', 'target_muscle', 'set_number', 'weight_kg', 'reps',
];

const List<String> FOOD_CSV_HEADER = [
  'date', 'time', 'food', 'quantity_g', 'kcal', 'protein_g', 'carbs_g', 'sugar_g',
  'fiber_g', 'fat_g', 'saturated_fat_g', 'sodium_mg',
];

/// Number without float noise: at most [decimals] places, no trailing zeros.
String csvNumber(double? value, {int decimals = 2}) {
  if (value == null) return '';
  var text = value.toStringAsFixed(decimals);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text == '-0' ? '0' : text;
}

/// workouts.csv: one row per set, local ISO dates.
String workoutsCsv(List<WorkoutExportRow> rows) => csv.encode([
  WORKOUT_CSV_HEADER,
  for (final r in rows)
    [
      dayKey(r.loggedAt),
      formatTime(r.loggedAt),
      r.sessionName,
      r.exerciseName,
      r.targetMuscle,
      '${r.setNumber}',
      csvNumber(r.weightKg, decimals: 3),
      '${r.reps}',
    ],
]);

/// food.csv: one row per entry; blank where unknown.
String foodCsv(List<FoodEntry> entries) => csv.encode([
  FOOD_CSV_HEADER,
  for (final e in entries)
    [
      dayKey(fromMillis(e.eatenAt)),
      formatTime(fromMillis(e.eatenAt)),
      e.name,
      csvNumber(e.quantityG),
      csvNumber(e.kcal),
      csvNumber(e.proteinG),
      csvNumber(e.carbsG),
      csvNumber(e.sugarG),
      csvNumber(e.fiberG),
      csvNumber(e.fatG),
      csvNumber(e.satFatG),
      csvNumber(e.sodiumMg),
    ],
]);
