import 'package:cms/app.dart';
import 'package:cms/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_db.dart';

void main() {
  testWidgets('boots to Home, opens Workout, starts and discards a Mix session', (tester) async {
    final db = openTestDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // The real dataset import is covered by seed_import_test.dart.
          exerciseDatasetProvider.overrideWithValue(() async => '[]'),
        ],
        child: const CountMySweatApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your progress this week'), findsOneWidget);
    expect(find.text('Start workout'), findsOneWidget);

    await tester.tap(find.text('Workout'));
    await tester.pumpAndSettle();
    expect(find.text('Tap + to create your first preset'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.text('Mix'), findsOneWidget);
    expect(find.text('Add exercise'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Resume workout'), findsOneWidget);

    await tester.tap(find.text('Resume workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'End session'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'End session').last);
    await tester.pumpAndSettle();
    expect(find.text('Start workout'), findsOneWidget);
    expect(await db.select(db.sessions).get(), isEmpty);

    // Dispose the tree so stream subscriptions close before the database.
    await tester.pumpWidget(const SizedBox());
  });
}
