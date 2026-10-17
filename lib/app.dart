import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'core/theme.dart';
import 'data/exercise_repository.dart';
import 'data/providers.dart';
import 'features/backup/backup_service.dart';
import 'features/home/home_screen.dart';

/// Reads the bundled exercise dataset (overridable in tests).
final exerciseDatasetProvider = Provider<Future<String> Function()>(
  (ref) => () => rootBundle.loadString(EXERCISES_JSON_ASSET),
);

/// First-launch seed import and auto-end of a forgotten session.
final startupProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(databaseProvider);
  await ExerciseSeeder(db).seedIfNeeded(ref.read(exerciseDatasetProvider));
  await ref.read(sessionRepositoryProvider).autoEndStale();
  await ref.read(backupServiceProvider).start();
});

class EasyRepsApp extends StatelessWidget {
  const EasyRepsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: APP_NAME,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _StartupGate(),
    );
  }
}

class _StartupGate extends ConsumerStatefulWidget {
  const _StartupGate();

  @override
  ConsumerState<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<_StartupGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(startupProvider).hasValue) return;
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(sessionRepositoryProvider).autoEndStale();
      case AppLifecycleState.paused:
        ref.read(backupServiceProvider).backupIfNeeded();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(startupProvider);
    return startup.when(
      data: (_) => const HomeScreen(),
      loading: () => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Getting things ready...'),
            ],
          ),
        ),
      ),
      error: (error, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not open the database.\n$error', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
