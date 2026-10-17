import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/nutrients.dart';
import '../../core/units.dart';
import 'summary.dart';

/// Built-in PDF fonts only cover Latin-1; keep the text plain ASCII.
String asciiOnly(String text) {
  const replacements = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'ß': 'ss',
    '’': "'", '‘': "'", '“': '"', '”': '"', '–': '-', '—': '-', '¾': '3/4', '½': '1/2',
  };
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    if (rune >= 32 && rune < 127) {
      buffer.write(char);
    } else if (replacements[lower] case final r?) {
      buffer.write(char == lower ? r : r.toUpperCase());
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}

Future<Uint8List> buildSummaryPdf({
  required DateTime firstDay,
  required DateTime lastDay,
  required WeightUnit unit,
  WorkoutSummary? workout,
  FoodSummary? food,
  DateTime? generatedAt,
}) {
  final doc = pw.Document(title: '$APP_NAME summary', creator: APP_NAME);
  String w(double kg) => formatWeight(kg, unit);

  pw.Widget heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
  );
  pw.Widget line(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(children: [
      pw.SizedBox(width: 220, child: pw.Text(asciiOnly(label))),
      pw.Expanded(child: pw.Text(asciiOnly(value))),
    ]),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      maxPages: 2,
      build: (context) => [
        pw.Text('$APP_NAME - summary', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Period: ${formatDate(firstDay)} - ${formatDate(lastDay)}'),
        pw.Text('Generated: ${formatDate(generatedAt ?? DateTime.now())}',
            style: const pw.TextStyle(color: PdfColors.grey700)),
        if (workout != null) ...[
          heading('Workout'),
          line('Sessions', '${workout.sessionCount}'),
          line('Total volume', w(workout.totalVolumeKg)),
          line(
            'Volume trend (1st vs 2nd half)',
            '${w(workout.firstHalfVolumeKg)} -> ${w(workout.secondHalfVolumeKg)}'
                '${workout.trendPercent == null ? '' : ' (${workout.trendPercent! >= 0 ? '+' : ''}${formatDecimal(workout.trendPercent!, decimals: 0)}%)'}',
          ),
          pw.SizedBox(height: 8),
          pw.Text('Personal records', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          if (workout.records.isEmpty)
            pw.Text('None in this period.', style: const pw.TextStyle(color: PdfColors.grey700))
          else
            pw.TableHelper.fromTextArray(
              headers: ['Exercise', 'New weight', 'Date'],
              data: [
                for (final r in workout.records)
                  [asciiOnly(r.exerciseName), w(r.weightKg), formatDate(r.date)],
              ],
              cellAlignment: pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
        ],
        if (food != null) ...[
          heading('Food'),
          line('Days with entries', '${food.loggedDays}'),
          pw.SizedBox(height: 4),
          pw.Text('Average per logged day', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          for (final n in Nutrient.HEADLINE) line(n.label, n.formatWithUnit(food.averages[n]!)),
          if (food.targets.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Targets', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            for (final t in food.targets)
              line(
                '${t.target.nutrient.label} ${t.target.kind.label} '
                    '${t.target.nutrient.formatWithUnit(t.target.value)}',
                '${t.target.kind == TargetKind.min ? 'met' : 'kept'} on '
                    '${t.daysOk} of ${food.loggedDays} days',
              ),
          ],
        ],
      ],
    ),
  );
  return doc.save();
}
