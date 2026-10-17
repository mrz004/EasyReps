import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../data/database.dart';
import '../../data/food_repository.dart';
import '../../data/providers.dart';
import 'add_food_screen.dart';
import 'entry_editor_sheet.dart';
import 'nutrition_card.dart';

final _entriesProvider = StreamProvider.autoDispose.family<List<FoodEntry>, String>(
  (ref, key) => ref.watch(foodRepositoryProvider).watchEntriesForDay(parseDayKey(key)),
);

class FoodLogScreen extends ConsumerStatefulWidget {
  const FoodLogScreen({super.key});

  @override
  ConsumerState<FoodLogScreen> createState() => _FoodLogScreenState();
}

class _FoodLogScreenState extends ConsumerState<FoodLogScreen> {
  DateTime _day = startOfDay(DateTime.now());

  bool get _isToday => _day == startOfDay(DateTime.now());

  Future<void> _edit(FoodEntry entry) async {
    final result = await showEntryEditor(context, entry: entry);
    if (result == null || !mounted) return;
    final foods = ref.read(foodRepositoryProvider);
    switch (result) {
      case EntryEditorDelete():
        await foods.deleteEntry(entry.id);
      case EntryEditorSave(:final entry, :final entryId):
        await foods.updateEntry(entryId!, entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(_entriesProvider(dayKey(_day))).value ?? const <FoodEntry>[];
    final targets = ref.watch(targetsProvider).value ?? const {};
    final totals = sumNutrients(entries);
    final overLimit = anyLimitExceeded(totals, targets);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              tooltip: 'Previous day',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _day = addDays(_day, -1)),
            ),
            Flexible(child: Text(formatDayLabel(_day), overflow: TextOverflow.ellipsis)),
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: _isToday ? null : () => setState(() => _day = addDays(_day, 1)),
            ),
          ],
        ),
        actions: [
          if (overLimit)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: 'An "at most" target is exceeded',
                child: Chip(
                  label: const Text('! limit'),
                  backgroundColor: scheme.error,
                  labelStyle: TextStyle(color: scheme.onError, fontWeight: FontWeight.bold),
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NutritionCard(totals: totals, targets: targets),
          const SectionHeader('Entries'),
          if (entries.isEmpty) const HintText('Nothing logged on this day', textAlign: TextAlign.start),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: Text(formatTime(fromMillis(e.eatenAt))),
                  title: Text(e.name),
                  trailing: Text(Nutrient.kcal.formatWithUnit(e.kcal)),
                  onTap: () => _edit(e),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddFoodScreen(day: _day)),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add food'),
          ),
        ),
      ),
    );
  }
}
