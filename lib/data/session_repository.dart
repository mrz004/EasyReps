import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../core/dates.dart';
import 'database.dart';

class ActiveSessionExistsException implements Exception {
  const ActiveSessionExistsException(this.activeSessionId);
  final int activeSessionId;

  @override
  String toString() => 'A session is already active';
}

class SessionNotActiveException implements Exception {
  const SessionNotActiveException();

  @override
  String toString() => 'This session has ended';
}

/// Mix sessions have no preset; the name check keeps sessions whose preset
/// was deleted from being treated as Mix.
bool isMixSession(Session s) => s.presetId == null && s.presetName == MIX_NAME;

/// One row of the Session screen.
class SessionExerciseItem {
  const SessionExerciseItem(this.exercise, this.setCount);
  final Exercise exercise;
  final int setCount;
}

sealed class EndResult {
  const EndResult();
}

/// The session had no sets and was deleted.
class SessionDiscarded extends EndResult {
  const SessionDiscarded();
}

class SessionEnded extends EndResult {
  const SessionEnded({required this.wasMix, required this.exerciseIdsDone});
  final bool wasMix;

  /// Exercises with at least one set, in order of their first set.
  final List<String> exerciseIdsDone;
}

class SessionRepository {
  SessionRepository(this.db);
  final AppDatabase db;

  int _now(DateTime? now) => (now ?? DateTime.now()).millisecondsSinceEpoch;

  Stream<Session?> watchActive() =>
      (db.select(db.sessions)..where((s) => s.endedAt.isNull()))
          .watchSingleOrNull();

  Future<Session?> getActive() =>
      (db.select(db.sessions)..where((s) => s.endedAt.isNull()))
          .getSingleOrNull();

  Future<Session?> byId(int id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id))).getSingleOrNull();

  Stream<Session?> watchById(int id) =>
      (db.select(db.sessions)..where((s) => s.id.equals(id)))
          .watchSingleOrNull();

  /// Starts a session from a preset, or a Mix session when [presetId] is null.
  /// Throws [ActiveSessionExistsException] if one is already active.
  Future<int> start(int? presetId, {DateTime? now}) {
    return db.transaction(() async {
      final active = await getActive();
      if (active != null) throw ActiveSessionExistsException(active.id);

      var name = MIX_NAME;
      if (presetId != null) {
        final preset = await (db.select(
          db.presets,
        )..where((p) => p.id.equals(presetId))).getSingle();
        name = preset.name;
      }
      final sessionId = await db.into(db.sessions).insert(
        SessionsCompanion.insert(
          presetId: Value(presetId),
          presetName: name,
          startedAt: _now(now),
        ),
      );
      if (presetId != null) {
        await db.customStatement(
          'INSERT INTO session_exercises (session_id, exercise_id, position) '
          'SELECT ?, exercise_id, position FROM preset_exercises '
          'WHERE preset_id = ?',
          [sessionId, presetId],
        );
      }
      return sessionId;
    });
  }

  /// Mix only: adds an exercise to the session list (no duplicates).
  Future<void> addExercise(int sessionId, String exerciseId) {
    return db.transaction(() async {
      await _requireActive(sessionId);
      final maxPos = db.sessionExercises.position.max();
      final row = await (db.selectOnly(db.sessionExercises)
            ..addColumns([maxPos])
            ..where(db.sessionExercises.sessionId.equals(sessionId)))
          .getSingle();
      final next = (row.read(maxPos) ?? -1) + 1;
      await db.into(db.sessionExercises).insert(
        SessionExercisesCompanion.insert(
          sessionId: sessionId,
          exerciseId: exerciseId,
          position: next,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  Stream<List<SessionExerciseItem>> watchSessionExercises(int sessionId) {
    return db
        .customSelect(
          'SELECT e.*, (SELECT COUNT(*) FROM sets st '
          '  WHERE st.session_id = se.session_id AND st.exercise_id = e.id) AS set_count '
          'FROM session_exercises se JOIN exercises e ON e.id = se.exercise_id '
          'WHERE se.session_id = ? ORDER BY se.position',
          variables: [Variable.withInt(sessionId)],
          readsFrom: {db.sessionExercises, db.exercises, db.sets},
        )
        .watch()
        .map(
          (rows) => [
            for (final r in rows)
              SessionExerciseItem(
                db.exercises.map(r.data),
                r.read<int>('set_count'),
              ),
          ],
        );
  }

  Stream<List<WorkoutSet>> watchSets(int sessionId, String exerciseId) =>
      (db.select(db.sets)
            ..where(
              (s) =>
                  s.sessionId.equals(sessionId) &
                  s.exerciseId.equals(exerciseId),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.loggedAt)]))
          .watch();

  /// Latest set of the session (any exercise), for the rest timer.
  Stream<WorkoutSet?> watchLastSet(int sessionId) =>
      (db.select(db.sets)
            ..where((s) => s.sessionId.equals(sessionId))
            ..orderBy([(s) => OrderingTerm.desc(s.loggedAt)])
            ..limit(1))
          .watchSingleOrNull();

  /// The most recent earlier set of this exercise, outside [excludeSessionId].
  Future<WorkoutSet?> lastEarlierSet(String exerciseId, int excludeSessionId) =>
      (db.select(db.sets)
            ..where(
              (s) =>
                  s.exerciseId.equals(exerciseId) &
                  s.sessionId.equals(excludeSessionId).not(),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.loggedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<int> logSet({
    required int sessionId,
    required String exerciseId,
    required double weightKg,
    required int reps,
    DateTime? now,
  }) {
    _checkSet(weightKg, reps);
    return db.transaction(() async {
      await _requireActive(sessionId);
      return db.into(db.sets).insert(
        SetsCompanion.insert(
          sessionId: sessionId,
          exerciseId: exerciseId,
          weightKg: weightKg,
          reps: reps,
          loggedAt: _now(now),
        ),
      );
    });
  }

  Future<void> updateSet(int setId, {required double weightKg, required int reps}) {
    _checkSet(weightKg, reps);
    return db.transaction(() async {
      final set = await (db.select(
        db.sets,
      )..where((s) => s.id.equals(setId))).getSingle();
      await _requireActive(set.sessionId);
      await (db.update(db.sets)..where((s) => s.id.equals(setId))).write(
        SetsCompanion(weightKg: Value(weightKg), reps: Value(reps)),
      );
    });
  }

  Future<void> deleteSet(int setId) {
    return db.transaction(() async {
      final set = await (db.select(
        db.sets,
      )..where((s) => s.id.equals(setId))).getSingleOrNull();
      if (set == null) return;
      await _requireActive(set.sessionId);
      await (db.delete(db.sets)..where((s) => s.id.equals(setId))).go();
    });
  }

  /// Ends the session, or deletes it when it has no sets.
  Future<EndResult> end(int sessionId, {DateTime? now}) {
    return db.transaction(() async {
      final session = await _requireActive(sessionId);
      final sets = await (db.select(db.sets)
            ..where((s) => s.sessionId.equals(sessionId))
            ..orderBy([(s) => OrderingTerm.asc(s.loggedAt)]))
          .get();
      if (sets.isEmpty) {
        await _deleteSession(sessionId);
        return const SessionDiscarded();
      }
      await (db.update(db.sessions)..where((s) => s.id.equals(sessionId)))
          .write(SessionsCompanion(endedAt: Value(_now(now))));
      final done = <String>[];
      for (final s in sets) {
        if (!done.contains(s.exerciseId)) done.add(s.exerciseId);
      }
      return SessionEnded(wasMix: isMixSession(session), exerciseIdsDone: done);
    });
  }

  /// Auto-ends an active session that started on an earlier local day,
  /// at its last set's time (or deletes it when it has no sets).
  /// Returns true when a session was closed.
  Future<bool> autoEndStale({DateTime? now}) {
    return db.transaction(() async {
      final active = await getActive();
      if (active == null) return false;
      final today = startOfDay(now ?? DateTime.now());
      if (!fromMillis(active.startedAt).isBefore(today)) return false;

      final last = await (db.select(db.sets)
            ..where((s) => s.sessionId.equals(active.id))
            ..orderBy([(s) => OrderingTerm.desc(s.loggedAt)])
            ..limit(1))
          .getSingleOrNull();
      if (last == null) {
        await _deleteSession(active.id);
      } else {
        await (db.update(db.sessions)..where((s) => s.id.equals(active.id)))
            .write(SessionsCompanion(endedAt: Value(last.loggedAt)));
      }
      return true;
    });
  }

  Future<void> _deleteSession(int id) async {
    await (db.delete(db.sessions)..where((s) => s.id.equals(id))).go();
  }

  Future<Session> _requireActive(int sessionId) async {
    final session = await byId(sessionId);
    if (session == null || session.endedAt != null) {
      throw const SessionNotActiveException();
    }
    return session;
  }

  void _checkSet(double weightKg, int reps) {
    if (weightKg.isNaN || weightKg.isInfinite || weightKg < 0 || reps < 1) {
      throw ArgumentError('Invalid set: $weightKg kg x $reps');
    }
  }
}
