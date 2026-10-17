import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/nutrients.dart';
import '../core/units.dart';
import 'database.dart';
import 'exercise_repository.dart';
import 'food_repository.dart';
import 'off_client.dart';
import 'preset_repository.dart';
import 'profile_repository.dart';
import 'session_repository.dart';
import 'stats_repository.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final exerciseRepositoryProvider = Provider(
  (ref) => ExerciseRepository(ref.watch(databaseProvider)),
);
final presetRepositoryProvider = Provider(
  (ref) => PresetRepository(ref.watch(databaseProvider)),
);
final sessionRepositoryProvider = Provider(
  (ref) => SessionRepository(ref.watch(databaseProvider)),
);
final foodRepositoryProvider = Provider(
  (ref) => FoodRepository(ref.watch(databaseProvider)),
);
final profileRepositoryProvider = Provider(
  (ref) => ProfileRepository(ref.watch(databaseProvider)),
);
final statsRepositoryProvider = Provider(
  (ref) => StatsRepository(ref.watch(databaseProvider)),
);
final offClientProvider = Provider((ref) => OffClient());

final activeSessionProvider = StreamProvider<Session?>(
  (ref) => ref.watch(sessionRepositoryProvider).watchActive(),
);

final weightUnitProvider = StreamProvider<WeightUnit>(
  (ref) => ref.watch(profileRepositoryProvider).watchWeightUnit(),
);

/// Current unit, kg until loaded.
final currentUnitProvider = Provider<WeightUnit>(
  (ref) => ref.watch(weightUnitProvider).value ?? WeightUnit.kg,
);

final targetsProvider = StreamProvider<Map<Nutrient, Target>>(
  (ref) => ref.watch(profileRepositoryProvider).watchTargets(),
);

final allExercisesProvider = StreamProvider<List<Exercise>>(
  (ref) => ref.watch(exerciseRepositoryProvider).watchAll(),
);

final presetSummariesProvider = StreamProvider<List<PresetSummary>>(
  (ref) => ref.watch(presetRepositoryProvider).watchSummaries(),
);

final weekVolumeProvider = StreamProvider<List<DailyValue>>(
  (ref) => ref.watch(statsRepositoryProvider).watchWeekVolume(),
);

final settingProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(profileRepositoryProvider).watchSetting(key),
);

final heightProvider = StreamProvider<double?>(
  (ref) => ref.watch(profileRepositoryProvider).watchHeightCm(),
);

final bodyWeightsProvider = StreamProvider<List<BodyWeight>>(
  (ref) => ref.watch(profileRepositoryProvider).watchBodyWeights(),
);

final driveConnectedProvider = Provider<bool>(
  (ref) => ref.watch(settingProvider(SETTING_DRIVE_CONNECTED)).value == 'true',
);
