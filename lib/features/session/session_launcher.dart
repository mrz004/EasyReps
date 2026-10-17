import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/session_repository.dart';
import 'session_screen.dart';

Future<void> openSession(BuildContext context, int sessionId) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => SessionScreen(sessionId: sessionId)),
);

/// Starts a preset session (or Mix when [presetId] is null) and opens it.
/// If a session is already active, offers to resume it instead.
Future<void> startSession(BuildContext context, WidgetRef ref, int? presetId) async {
  final sessions = ref.read(sessionRepositoryProvider);
  try {
    final id = await sessions.start(presetId);
    if (context.mounted) await openSession(context, id);
  } on ActiveSessionExistsException catch (e) {
    if (!context.mounted) return;
    final active = await sessions.byId(e.activeSessionId);
    if (!context.mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A workout is in progress'),
        content: Text(
          'Finish "${active?.presetName ?? 'your session'}" before starting another one.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (resume == true && context.mounted) await openSession(context, e.activeSessionId);
  }
}
