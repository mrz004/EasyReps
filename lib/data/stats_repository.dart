import 'package:drift/drift.dart';

import '../core/dates.dart';
import '../core/nutrients.dart';
import 'database.dart';
import 'food_repository.dart';

/// One value per local day.
class DailyValue {
  const DailyValue(this.day, this.value);
  final DateTime day;
  final double value;
}

/// A local-day range; [first] null means "from the earliest data".
class DayRange {
  const DayRange(this.first, this.last);
  final DateTime? first;
  final DateTime last;

  /// The last [days] days including today.
  factory DayRange.lastDays(int days, {DateTime? now}) {
    final today = startOfDay(now ?? DateTime.now());
    return DayRange(addDays(today, -(days - 1)), today);
  }

  factory DayRange.all({DateTime? now}) =>
      DayRange(null, startOfDay(now ?? DateTime.now()));

  int? get fromMs => first == null ? null : startOfDay(first!).millisecondsSinceEpoch;
  int get toMsExclusive => addDays(startOfDay(last), 1).millisecondsSinceEpoch;

  bool containsMs(int ms) =>
      (fromMs == null || ms >= fromMs!) && ms < toMsExclusive;
}

/// Computes stats from raw sets and food entries (nothing derived is stored).
class StatsRepository {
  StatsRepository(this.db);
  final AppDatabase db;

  /// Training volume (sum of weight x reps) per local day, zero-filled.
  Stream<List<DailyValue>> watchVolumePerDay(DayRange range) {
    final query = db.select(db.sets)
      ..where((s) {
        final upper = s.loggedAt.isSmallerThanValue(range.toMsExclusive);
        final from = range.fromMs;
        return from == null ? upper : upper & s.loggedAt.isBiggerOrEqualValue(from);
      });
    return query.watch().map(
      (sets) => zeroFill(
        {
          for (final entry in _groupByDay(sets, (s) => s.loggedAt).entries)
            entry.key: entry.value.fold<double>(0, (sum, s) => sum + s.weightKg * s.reps),
        },
        range,
      ),
    );
  }

  /// Daily intake of [nutrient], zero-filled.
  Stream<List<DailyValue>> watchIntakePerDay(DayRange range, Nutrient nutrient) {
    return _entriesIn(range).watch().map(
      (entries) => zeroFill(
        {
          for (final entry in _groupByDay(entries, (e) => e.eatenAt).entries)
            entry.key: sumNutrients(entry.value)[nutrient]!,
        },
        range,
      ),
    );
  }

  /// Total volume per day for the 7 days ending today.
  Stream<List<DailyValue>> watchWeekVolume() =>
      watchVolumePerDay(DayRange.lastDays(7));

  SimpleSelectStatement<$FoodEntriesTable, FoodEntry> _entriesIn(DayRange range) =>
      db.select(db.foodEntries)
        ..where((e) {
          final upper = e.eatenAt.isSmallerThanValue(range.toMsExclusive);
          final from = range.fromMs;
          return from == null ? upper : upper & e.eatenAt.isBiggerOrEqualValue(from);
        });

  static Map<DateTime, List<T>> _groupByDay<T>(List<T> items, int Function(T) ms) {
    final map = <DateTime, List<T>>{};
    for (final item in items) {
      map.putIfAbsent(startOfDay(fromMillis(ms(item))), () => []).add(item);
    }
    return map;
  }

  /// One point per day of [range]; an open range starts at the first data day.
  static List<DailyValue> zeroFill(Map<DateTime, double> byDay, DayRange range) {
    DateTime? first = range.first;
    if (first == null) {
      if (byDay.isEmpty) return [];
      first = byDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    }
    return [
      for (final day in daysBetween(first, range.last)) DailyValue(day, byDay[day] ?? 0),
    ];
  }
}
