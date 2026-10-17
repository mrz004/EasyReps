import 'package:cms/core/constants.dart';
import 'package:cms/data/database.dart';
import 'package:cms/data/preset_repository.dart';
import 'package:cms/data/session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessions;
  late PresetRepository presets;

  setUp(() async {
    db = openTestDb();
    sessions = SessionRepository(db);
    presets = PresetRepository(db);
    await addExercise(db, 'Bench_Press');
    await addExercise(db, 'Cable_Fly');
    await addExercise(db, 'Squat', muscle: 'quadriceps');
  });

  tearDown(() => db.close());

  test('start from preset copies its exercises in order', () async {
    final presetId = await presets.save(
      name: 'Chest Day',
      preferredDays: 1,
      exerciseIds: ['Cable_Fly', 'Bench_Press'],
    );
    final id = await sessions.start(presetId);
    final session = (await sessions.byId(id))!;
    expect(session.presetName, 'Chest Day');
    expect(isMixSession(session), isFalse);
    final items = await sessions.watchSessionExercises(id).first;
    expect(items.map((i) => i.exercise.id), ['Cable_Fly', 'Bench_Press']);
  });

  test('only one active session; starting another is blocked', () async {
    final id = await sessions.start(null);
    expect(
      () => sessions.start(null),
      throwsA(isA<ActiveSessionExistsException>().having((e) => e.activeSessionId, 'id', id)),
    );
  });

  test('Mix adds exercises without duplicates and saves nothing to presets', () async {
    final id = await sessions.start(null);
    expect((await sessions.byId(id))!.presetName, MIX_NAME);
    await sessions.addExercise(id, 'Squat');
    await sessions.addExercise(id, 'Bench_Press');
    await sessions.addExercise(id, 'Squat');
    final items = await sessions.watchSessionExercises(id).first;
    expect(items.map((i) => i.exercise.id), ['Squat', 'Bench_Press']);
    expect(await db.select(db.presets).get(), isEmpty);
  });

  test('ending with zero sets discards the session', () async {
    final id = await sessions.start(null);
    final result = await sessions.end(id);
    expect(result, isA<SessionDiscarded>());
    expect(await sessions.byId(id), isNull);
  });

  test('ending a Mix with sets returns exercises in order of first set', () async {
    final id = await sessions.start(null);
    final t = DateTime(2026, 10, 1, 10);
    await sessions.addExercise(id, 'Bench_Press');
    await sessions.addExercise(id, 'Squat');
    await sessions.logSet(sessionId: id, exerciseId: 'Squat', weightKg: 100, reps: 5, now: t);
    await sessions.logSet(
      sessionId: id, exerciseId: 'Bench_Press', weightKg: 60, reps: 8,
      now: t.add(const Duration(minutes: 3)),
    );
    final result = await sessions.end(id, now: t.add(const Duration(minutes: 10)));
    expect(result, isA<SessionEnded>());
    final ended = result as SessionEnded;
    expect(ended.wasMix, isTrue);
    expect(ended.exerciseIdsDone, ['Squat', 'Bench_Press']);
    expect((await sessions.byId(id))!.endedAt, isNotNull);
    // Sets of an ended session can no longer be changed.
    final set = (await db.select(db.sets).get()).first;
    expect(() => sessions.deleteSet(set.id), throwsA(isA<SessionNotActiveException>()));
  });

  test('prefill uses the most recent earlier set outside the current session', () async {
    final first = await sessions.start(null);
    await sessions.logSet(
      sessionId: first, exerciseId: 'Squat', weightKg: 90, reps: 5, now: DateTime(2026, 9, 1),
    );
    await sessions.logSet(
      sessionId: first, exerciseId: 'Squat', weightKg: 95, reps: 4, now: DateTime(2026, 9, 1, 0, 5),
    );
    await sessions.end(first, now: DateTime(2026, 9, 1, 1));
    final second = await sessions.start(null);
    await sessions.logSet(sessionId: second, exerciseId: 'Squat', weightKg: 120, reps: 1);
    final prefill = await sessions.lastEarlierSet('Squat', second);
    expect(prefill!.weightKg, 95);
    expect(prefill.reps, 4);
  });

  test('auto-end: stale session ends at its last set; empty one is deleted', () async {
    final yesterday = DateTime(2026, 10, 17, 18);
    final today = DateTime(2026, 10, 18, 9);

    final id = await sessions.start(null, now: yesterday);
    await sessions.logSet(
      sessionId: id, exerciseId: 'Squat', weightKg: 80, reps: 5,
      now: yesterday.add(const Duration(minutes: 20)),
    );
    expect(await sessions.autoEndStale(now: today), isTrue);
    final ended = (await sessions.byId(id))!;
    expect(ended.endedAt, yesterday.add(const Duration(minutes: 20)).millisecondsSinceEpoch);

    final empty = await sessions.start(null, now: yesterday);
    expect(await sessions.autoEndStale(now: today), isTrue);
    expect(await sessions.byId(empty), isNull);

    final current = await sessions.start(null, now: today);
    expect(await sessions.autoEndStale(now: today.add(const Duration(hours: 2))), isFalse);
    expect((await sessions.byId(current))!.endedAt, isNull);
  });

  test('deleting a preset keeps past sessions and sets', () async {
    final presetId = await presets.save(name: 'Legs', preferredDays: 0, exerciseIds: ['Squat']);
    final id = await sessions.start(presetId);
    await sessions.logSet(sessionId: id, exerciseId: 'Squat', weightKg: 100, reps: 5);
    await sessions.end(id);
    await presets.delete(presetId);
    final session = (await sessions.byId(id))!;
    expect(session.presetId, isNull);
    expect(session.presetName, 'Legs');
    expect(isMixSession(session), isFalse);
    expect(await db.select(db.sets).get(), hasLength(1));
  });

  test('invalid sets are rejected', () async {
    final id = await sessions.start(null);
    expect(
      () => sessions.logSet(sessionId: id, exerciseId: 'Squat', weightKg: -1, reps: 5),
      throwsArgumentError,
    );
    expect(
      () => sessions.logSet(sessionId: id, exerciseId: 'Squat', weightKg: 10, reps: 0),
      throwsArgumentError,
    );
  });
}
