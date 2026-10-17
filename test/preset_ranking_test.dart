import 'package:cms/core/dates.dart';
import 'package:cms/data/database.dart';
import 'package:cms/data/preset_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

PresetSummary summary(
  int id,
  String name, {
  int days = 0,
  int recent = 0,
  int? lastStarted,
}) => PresetSummary(
  preset: Preset(id: id, name: name, preferredDays: days, createdAt: 0),
  exerciseCount: 3,
  recentFinishedCount: recent,
  lastStartedAt: lastStarted,
);

void main() {
  // 2026-10-19 is a Monday.
  final monday = DateTime(2026, 10, 19, 9);

  test('presets preferred today come first, each group by use, recency, name', () {
    final ranked = rankPresets([
      summary(1, 'Legs', recent: 9, lastStarted: 500),
      summary(2, 'Chest', days: weekdayBit(DateTime.monday), recent: 1, lastStarted: 100),
      summary(3, 'Back', days: weekdayBit(DateTime.monday), recent: 4, lastStarted: 50),
      summary(4, 'Arms', recent: 9, lastStarted: 900),
      summary(5, 'Core'),
      summary(6, 'Abs'),
      summary(7, 'Push', days: weekdayBit(DateTime.monday), recent: 1, lastStarted: 300),
    ], monday);
    expect(ranked.map((s) => s.preset.name), [
      // Group A (Monday): by count, then most recent start.
      'Back', 'Push', 'Chest',
      // Group B: by count, then recency, never-used last and by name.
      'Arms', 'Legs', 'Abs', 'Core',
    ]);
  });

  test('summaries count only finished sessions in the last 60 days', () async {
    final db = openTestDb();
    addTearDown(db.close);
    final repo = PresetRepository(db);
    await addExercise(db, 'Squat');
    final id = await repo.save(name: 'Legs', preferredDays: 0, exerciseIds: ['Squat']);
    final now = DateTime(2026, 10, 18);
    Future<void> session(DateTime start, {bool finished = true}) => db.into(db.sessions).insert(
      SessionsCompanion.insert(
        presetId: Value(id),
        presetName: 'Legs',
        startedAt: start.millisecondsSinceEpoch,
        endedAt: Value(finished ? start.millisecondsSinceEpoch + 1 : null),
      ),
    );
    await session(now.subtract(const Duration(days: 70)));
    await session(now.subtract(const Duration(days: 10)));
    await session(now.subtract(const Duration(days: 1)), finished: false);

    final result = (await repo.watchSummaries(clock: () => now).first).single;
    expect(result.exerciseCount, 1);
    expect(result.recentFinishedCount, 1);
    expect(result.lastStartedAt, now.subtract(const Duration(days: 1)).millisecondsSinceEpoch);
  });
}
