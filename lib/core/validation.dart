/// Input parsing and validation shared by all forms.
/// Each `...Error` function returns null when the input is valid.
library;

/// Parses a decimal typed by the user. Accepts a comma as decimal separator.
/// Returns null for empty, NaN or infinite input.
double? tryParseDecimal(String text) {
  final normalised = text.trim().replaceAll(',', '.');
  if (normalised.isEmpty) return null;
  final value = double.tryParse(normalised);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return value;
}

int? tryParseInt(String text) => int.tryParse(text.trim());

String? nameError(String text) =>
    text.trim().isEmpty ? 'Enter a name' : null;

/// Weight: number >= 0 (0 allowed for bodyweight).
String? weightError(String text) {
  final value = tryParseDecimal(text);
  if (value == null) return 'Enter a number';
  if (value < 0) return 'Must be 0 or more';
  return null;
}

/// Reps: integer >= 1.
String? repsError(String text) {
  final value = tryParseInt(text);
  if (value == null) return 'Enter a whole number';
  if (value < 1) return 'At least 1';
  return null;
}

/// Nutrient values: number >= 0. Empty is allowed unless [required].
String? nutrientError(String text, {bool required = false}) {
  if (text.trim().isEmpty) return required ? 'Required' : null;
  final value = tryParseDecimal(text);
  if (value == null) return 'Enter a number';
  if (value < 0) return 'Must be 0 or more';
  return null;
}

/// Quantity in grams (or any strictly positive amount).
String? positiveError(String text, {bool required = true}) {
  if (text.trim().isEmpty) return required ? 'Required' : null;
  final value = tryParseDecimal(text);
  if (value == null) return 'Enter a number';
  if (value <= 0) return 'Must be more than 0';
  return null;
}
