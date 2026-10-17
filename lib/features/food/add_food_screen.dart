import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../core/ui.dart';
import '../../core/units.dart';
import '../../core/validation.dart';
import '../../data/database.dart';
import '../../data/food_repository.dart';
import '../../data/off_client.dart';
import '../../data/providers.dart';
import 'custom_food_screen.dart';
import 'entry_editor_sheet.dart';
import 'food_amount_sheet.dart';

class AddFoodScreen extends ConsumerStatefulWidget {
  const AddFoodScreen({super.key, required this.day});

  /// Local day the entry is logged on.
  final DateTime day;

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  final _search = TextEditingController();
  final _quickFormKey = GlobalKey<FormState>();
  final _quickKcal = TextEditingController();
  final _quickProtein = TextEditingController();
  final _quickName = TextEditingController();

  Timer? _debounce;
  int _searchSeq = 0;
  List<FoodEntry> _recent = [];
  List<Food> _local = [];
  List<Food> _remote = [];
  bool _searching = false;
  String? _searchStatus;

  @override
  void initState() {
    super.initState();
    ref.read(foodRepositoryProvider).recentEntries().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _quickKcal.dispose();
    _quickProtein.dispose();
    _quickName.dispose();
    super.dispose();
  }

  /// Today: now. Other days: that day at the current time of day.
  DateTime get _eatenAt {
    final now = DateTime.now();
    if (isSameDay(widget.day, now)) return now;
    return DateTime(widget.day.year, widget.day.month, widget.day.day, now.hour, now.minute);
  }

  String get _query => _search.text.trim();

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    final seq = ++_searchSeq;
    if (_query.length < OFF_MIN_QUERY_LENGTH) {
      setState(() {
        _local = [];
        _remote = [];
        _searching = false;
        _searchStatus = null;
      });
      return;
    }
    // The local cache answers at once and keeps working offline.
    ref.read(foodRepositoryProvider).searchLocal(_query).then((foods) {
      if (mounted && seq == _searchSeq) setState(() => _local = foods);
    });
    _debounce = Timer(OFF_DEBOUNCE, () => _searchRemote(seq));
  }

  Future<void> _searchRemote(int seq) async {
    final query = _query;
    setState(() {
      _searching = true;
      _searchStatus = null;
    });
    String? status;
    var remote = <Food>[];
    try {
      final found = await ref.read(offClientProvider).search(query);
      remote = await ref.read(foodRepositoryProvider).cacheOffFoods(found);
      if (remote.isEmpty) status = 'No results on Open Food Facts';
    } on OffRateLimitedException {
      status = 'Too many searches - wait a minute. Saved foods still work.';
    } on OffUnavailableException catch (e) {
      status = e.message;
    }
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _remote = remote;
      _searching = false;
      _searchStatus = status;
    });
  }

  Future<void> _addEntry(FoodEntriesCompanion entry) async {
    await ref.read(foodRepositoryProvider).addEntry(entry);
    if (!mounted) return;
    showSnack(context, 'Added ${entry.name.value}');
    Navigator.pop(context);
  }

  Future<void> _chooseFood(Food food) async {
    final entry = await showFoodAmountSheet(context, food: food, eatenAt: _eatenAt);
    if (entry != null) await _addEntry(entry);
  }

  Future<void> _addRecent(FoodEntry template) async {
    final result = await showEntryEditor(context, template: template, eatenAt: _eatenAt);
    if (result is EntryEditorSave) await _addEntry(result.entry);
  }

  Future<void> _quickAdd() async {
    if (!_quickFormKey.currentState!.validate()) return;
    final name = _quickName.text.trim().isEmpty ? 'Quick add' : _quickName.text;
    await _addEntry(
      NutrientValues(
        kcal: tryParseDecimal(_quickKcal.text)!,
        proteinG: tryParseDecimal(_quickProtein.text),
      ).toEntry(name: name, eatenAt: _eatenAt),
    );
  }

  Future<void> _createCustom() async {
    final food = await Navigator.push<Food>(
      context,
      MaterialPageRoute(builder: (_) => CustomFoodScreen(initialName: _query)),
    );
    if (food != null && mounted) await _chooseFood(food);
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.length >= OFF_MIN_QUERY_LENGTH;
    final localIds = {for (final f in _local) f.id};
    final results = [..._local, ..._remote.where((f) => !localIds.contains(f.id))];

    return Scaffold(
      appBar: AppBar(title: Text('Add food - ${formatDayLabel(widget.day)}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            autofocus: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search food',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _onQueryChanged('');
                      },
                    ),
            ),
            onChanged: _onQueryChanged,
          ),
          if (searching) ...[
            SectionHeader(
              'Search results',
              trailing: _searching
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
            if (_searchStatus != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: HintText(_searchStatus!, textAlign: TextAlign.start),
              ),
            for (final f in results) _foodTile(f),
            if (!_searching && results.isEmpty && _searchStatus == null)
              const HintText('No foods found', textAlign: TextAlign.start),
          ] else ...[
            if (_recent.isNotEmpty) const SectionHeader('Recent'),
            for (final e in _recent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    title: Text(e.name),
                    subtitle: e.quantityG == null ? null : Text('${formatDecimal(e.quantityG!)} g'),
                    trailing: Text(Nutrient.kcal.formatWithUnit(e.kcal)),
                    onTap: () => _addRecent(e),
                  ),
                ),
              ),
          ],
          const SectionHeader('Quick add'),
          Form(
            key: _quickFormKey,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quickKcal,
                        keyboardType: DECIMAL_KEYBOARD,
                        inputFormatters: decimalInputFormatters,
                        decoration: const InputDecoration(labelText: 'kcal'),
                        validator: (v) => nutrientError(v ?? '', required: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _quickProtein,
                        keyboardType: DECIMAL_KEYBOARD,
                        inputFormatters: decimalInputFormatters,
                        decoration: const InputDecoration(labelText: 'protein g'),
                        validator: (v) => nutrientError(v ?? ''),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _quickName,
                        decoration: const InputDecoration(labelText: 'Name (optional)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: _quickAdd, child: const Text('Add')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _createCustom,
            icon: const Icon(Icons.add),
            label: const Text('Custom food'),
          ),
          const SizedBox(height: 24),
          const HintText('Food search data from Open Food Facts (openfoodfacts.org), available under the ODbL.'),
        ],
      ),
    );
  }

  Widget _foodTile(Food f) {
    final subtitle = [
      ?f.brand,
      '${Nutrient.kcal.formatWithUnit(f.kcal)} / 100 g',
      if (f.source == 'custom') 'custom',
    ].join('  -  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          title: Text(f.name),
          subtitle: Text(subtitle),
          onTap: () => _chooseFood(f),
        ),
      ),
    );
  }
}
