import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/units.dart';
import '../../data/database.dart';
import '../../data/profile_repository.dart';
import '../../data/stats_repository.dart';
import 'csv_export.dart';
import 'export_data.dart';
import 'pdf_export.dart';
import 'summary.dart';

enum ExportFormat { csv, pdf }

class ExportRequest {
  const ExportRequest({
    required this.format,
    required this.range,
    required this.includeWorkout,
    required this.includeFood,
  });

  final ExportFormat format;
  final DayRange range;
  final bool includeWorkout;
  final bool includeFood;
}

/// Builds export files and opens the share sheet.
class ExportService {
  ExportService(this.db) : _data = ExportData(db), _profile = ProfileRepository(db);
  final AppDatabase db;
  final ExportData _data;
  final ProfileRepository _profile;

  /// Returns false (and creates no file) when the range holds no data for the
  /// ticked sections.
  Future<bool> run(ExportRequest request) async {
    final workouts = request.includeWorkout
        ? await _data.workoutRows(request.range)
        : const <WorkoutExportRow>[];
    final food = request.includeFood
        ? await _data.foodEntries(request.range)
        : const <FoodEntry>[];
    if (workouts.isEmpty && food.isEmpty) return false;

    final files = switch (request.format) {
      ExportFormat.csv => await _csvFiles(workouts, food, request),
      ExportFormat.pdf => [await _pdfFile(workouts, food, request)],
    };
    await SharePlus.instance.share(ShareParams(files: files));
    return true;
  }

  Future<Directory> _exportDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/exports');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    return dir.create(recursive: true);
  }

  Future<List<XFile>> _csvFiles(
    List<WorkoutExportRow> workouts,
    List<FoodEntry> food,
    ExportRequest request,
  ) async {
    final dir = await _exportDir();
    final files = <XFile>[];
    Future<void> write(String name, String content) async {
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(utf8.encode(content), flush: true);
      files.add(XFile(file.path, mimeType: 'text/csv'));
    }

    if (request.includeWorkout && workouts.isNotEmpty) {
      await write('workouts.csv', workoutsCsv(workouts));
    }
    if (request.includeFood && food.isNotEmpty) await write('food.csv', foodCsv(food));
    return files;
  }

  Future<XFile> _pdfFile(
    List<WorkoutExportRow> workouts,
    List<FoodEntry> food,
    ExportRequest request,
  ) async {
    final range = request.range;
    final firstDay = range.first ?? _earliestDay(workouts, food);
    final unit = WeightUnit.fromKey(await _profile.getSetting(SETTING_WEIGHT_UNIT));
    final bytes = await buildSummaryPdf(
      firstDay: firstDay,
      lastDay: range.last,
      unit: unit,
      workout: request.includeWorkout && workouts.isNotEmpty
          ? summariseWorkouts(
              workouts,
              await _data.maxWeightBefore(startOfDay(firstDay).millisecondsSinceEpoch),
              firstDay,
              range.last,
            )
          : null,
      food: request.includeFood && food.isNotEmpty
          ? summariseFood(food, await _profile.getTargets())
          : null,
    );
    final dir = await _exportDir();
    final file = File('${dir.path}/count-my-sweat-summary-${dayKey(range.last)}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return XFile(file.path, mimeType: 'application/pdf');
  }

  DateTime _earliestDay(List<WorkoutExportRow> workouts, List<FoodEntry> food) {
    final candidates = [
      if (workouts.isNotEmpty) workouts.first.loggedAt,
      if (food.isNotEmpty) fromMillis(food.first.eatenAt),
    ];
    return startOfDay(candidates.reduce((a, b) => a.isBefore(b) ? a : b));
  }
}
