import 'constants.dart';

enum WeightUnit {
  kg,
  lb;

  String get label => name;

  static WeightUnit fromKey(String? key) => key == 'lb' ? lb : kg;
}

/// Converts a stored kg value to the display unit (full precision).
double kgToUnit(double kg, WeightUnit unit) =>
    unit == WeightUnit.lb ? kg * LB_PER_KG : kg;

/// Converts a user-entered value in [unit] to kg (full precision).
double unitToKg(double value, WeightUnit unit) =>
    unit == WeightUnit.lb ? value / LB_PER_KG : value;

/// Rounds to 0.1 and drops a trailing ".0".
String formatDecimal(double value, {int decimals = 1}) {
  final fixed = value.toStringAsFixed(decimals);
  if (!fixed.contains('.')) return fixed;
  final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// Display string for a weight stored in kg, e.g. "60 kg" or "132.3 lb".
String formatWeight(double kg, WeightUnit unit, {bool withUnit = true}) {
  final text = formatDecimal(kgToUnit(kg, unit));
  return withUnit ? '$text ${unit.label}' : text;
}
