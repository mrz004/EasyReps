import 'units.dart';

enum TargetKind {
  min('min', 'at least'),
  max('max', 'at most');

  const TargetKind(this.key, this.label);
  final String key;
  final String label;

  static TargetKind fromKey(String key) => key == 'max' ? max : min;
}

enum Nutrient {
  kcal('kcal', 'Calories', 'kcal', TargetKind.min),
  proteinG('protein_g', 'Protein', 'g', TargetKind.min),
  carbsG('carbs_g', 'Carbs', 'g', TargetKind.min),
  fatG('fat_g', 'Fat', 'g', TargetKind.max),
  satFatG('sat_fat_g', 'Saturated fat', 'g', TargetKind.max),
  sugarG('sugar_g', 'Sugar', 'g', TargetKind.max),
  fiberG('fiber_g', 'Fiber', 'g', TargetKind.min),
  sodiumMg('sodium_mg', 'Sodium', 'mg', TargetKind.max);

  const Nutrient(this.key, this.label, this.unit, this.defaultKind);

  /// Column / settings key, e.g. "protein_g".
  final String key;
  final String label;
  final String unit;

  /// Suggested "at least" / "at most" when a target is first set.
  final TargetKind defaultKind;

  static Nutrient? fromKey(String key) {
    for (final n in values) {
      if (n.key == key) return n;
    }
    return null;
  }

  /// Shown on the Food log headline card.
  static const List<Nutrient> HEADLINE = [kcal, proteinG, carbsG, fatG];

  /// Shown under "Show details" (non-saturated fat is derived, see below).
  static const List<Nutrient> DETAILS = [sugarG, fiberG, satFatG, sodiumMg];

  String format(double value) {
    final digits = this == kcal || this == sodiumMg ? 0 : 1;
    return formatDecimal(value, decimals: digits);
  }

  String formatWithUnit(double value) =>
      this == kcal ? '${format(value)} kcal' : '${format(value)} $unit';
}

/// Fat that is not saturated. Null unless both values are known and consistent.
double? nonSaturatedFat(double? fatG, double? satFatG) {
  if (fatG == null || satFatG == null || fatG < satFatG) return null;
  return fatG - satFatG;
}

/// A target status for one nutrient on one day.
enum TargetStatus { none, below, met, kept, exceeded }

TargetStatus targetStatus(double total, double? targetValue, TargetKind? kind) {
  if (targetValue == null || kind == null) return TargetStatus.none;
  if (kind == TargetKind.min) {
    return total >= targetValue ? TargetStatus.met : TargetStatus.below;
  }
  return total > targetValue ? TargetStatus.exceeded : TargetStatus.kept;
}

/// Nutrient amounts for a quantity of a food, from its per-100 g values.
double? scalePer100g(double? per100g, double quantityG) =>
    per100g == null ? null : per100g * quantityG / 100;
