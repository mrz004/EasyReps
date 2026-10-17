import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/database.dart';
import '../../data/providers.dart';

final _lastSetProvider = StreamProvider.autoDispose.family<WorkoutSet?, int>(
  (ref, sessionId) => ref.watch(sessionRepositoryProvider).watchLastSet(sessionId),
);

/// Time since the last set of the session, computed from `logged_at` so it
/// survives the app being backgrounded.
class RestTimer extends ConsumerStatefulWidget {
  const RestTimer({super.key, required this.sessionId});
  final int sessionId;

  @override
  ConsumerState<RestTimer> createState() => _RestTimerState();
}

class _RestTimerState extends ConsumerState<RestTimer> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = ref.watch(_lastSetProvider(widget.sessionId)).value;
    final text = last == null
        ? 'Rest timer starts after your first set'
        : 'Rest: ${formatElapsed(DateTime.now().difference(fromMillis(last.loggedAt)))} since last set';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
