import 'package:cms/core/nutrients.dart';
import 'package:cms/core/units.dart';
import 'package:cms/core/validation.dart';
import 'package:cms/data/off_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unit conversion', () {
    test('kg is stored as entered; lb converts with full precision', () {
      expect(unitToKg(60, WeightUnit.kg), 60);
      expect(unitToKg(135, WeightUnit.lb), closeTo(61.2350, 0.0001));
      expect(kgToUnit(unitToKg(135, WeightUnit.lb), WeightUnit.lb), closeTo(135, 1e-9));
    });

    test('display rounds to 0.1 and trims .0', () {
      expect(formatWeight(60, WeightUnit.kg), '60 kg');
      expect(formatWeight(60, WeightUnit.lb), '132.3 lb');
      expect(formatWeight(62.25, WeightUnit.kg, withUnit: false), '62.3');
      expect(formatWeight(0, WeightUnit.kg), '0 kg');
    });
  });

  group('validation', () {
    test('weight allows 0, rejects negatives and junk', () {
      expect(weightError('0'), isNull);
      expect(weightError('62,5'), isNull);
      expect(tryParseDecimal('62,5'), 62.5);
      expect(weightError('-1'), isNotNull);
      expect(weightError('NaN'), isNotNull);
      expect(weightError(''), isNotNull);
    });

    test('reps must be a whole number >= 1', () {
      expect(repsError('8'), isNull);
      expect(repsError('0'), isNotNull);
      expect(repsError('2.5'), isNotNull);
    });

    test('quantity must be > 0; names must not be blank', () {
      expect(positiveError('0'), isNotNull);
      expect(positiveError('150'), isNull);
      expect(nameError('   '), isNotNull);
    });
  });

  group('derived non-saturated fat', () {
    test('fat minus saturated fat when both known and consistent', () {
      expect(nonSaturatedFat(10, 4), 6);
      expect(nonSaturatedFat(4, 4), 0);
    });

    test('null when unknown or inconsistent', () {
      expect(nonSaturatedFat(null, 4), isNull);
      expect(nonSaturatedFat(10, null), isNull);
      expect(nonSaturatedFat(3, 4), isNull);
    });
  });

  test('target status', () {
    expect(targetStatus(150, 140, TargetKind.min), TargetStatus.met);
    expect(targetStatus(100, 140, TargetKind.min), TargetStatus.below);
    expect(targetStatus(25, 20, TargetKind.max), TargetStatus.exceeded);
    expect(targetStatus(20, 20, TargetKind.max), TargetStatus.kept);
    expect(targetStatus(20, null, null), TargetStatus.none);
  });

  group('Open Food Facts hit parsing', () {
    test('per-100 g values, sodium g -> mg, kJ fallback', () {
      final food = parseHit({
        'code': '123',
        'product_name': 'Oat Milk',
        'brands': ['Boring'],
        'serving_quantity': '250',
        'nutriments': {
          'energy-kj_100g': 190,
          'proteins_100g': 0.8,
          'fat_100g': 1.7,
          'saturated-fat_100g': 0.3,
          'sodium_100g': 0.048,
        },
      })!;
      expect(food.name.value, 'Oat Milk');
      expect(food.brand.value, 'Boring');
      expect(food.servingG.value, 250);
      expect(food.kcal.value, closeTo(190 / 4.184, 1e-9));
      expect(food.sodiumMg.value, closeTo(48, 1e-9));
      expect(food.carbsG.value, isNull);
    });

    test('hits without a name or energy are skipped', () {
      expect(parseHit({'code': '1', 'product_name': '', 'nutriments': {'energy-kcal_100g': 5}}), isNull);
      expect(parseHit({'code': '1', 'product_name': 'X', 'nutriments': {}}), isNull);
    });
  });
}
