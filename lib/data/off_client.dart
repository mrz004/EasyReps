import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'database.dart';

class OffRateLimitedException implements Exception {
  const OffRateLimitedException();
}

class OffUnavailableException implements Exception {
  const OffUnavailableException(this.message);
  final String message;
}

/// Open Food Facts search via the Search-a-licious API
/// (https://search.openfoodfacts.org/docs). The legacy /cgi/search.pl is not used.
class OffClient {
  OffClient({http.Client? client, DateTime Function()? clock})
    : _client = client ?? http.Client(),
      _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;
  final List<DateTime> _recentRequests = [];

  static const String _FIELDS =
      'code,product_name,brands,serving_quantity,nutriments';

  /// Returns foods ready to cache (source 'off'). Throws
  /// [OffRateLimitedException] or [OffUnavailableException].
  Future<List<FoodsCompanion>> search(String query) async {
    _checkRateLimit();
    final uri = Uri.parse(OFF_SEARCH_URL).replace(
      queryParameters: {'q': query.trim(), 'page_size': '20', 'fields': _FIELDS},
    );
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'User-Agent': OFF_USER_AGENT})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const OffUnavailableException('Open Food Facts did not answer');
    } on Exception {
      throw const OffUnavailableException('Offline - showing saved foods only');
    }
    if (response.statusCode == 429) throw const OffRateLimitedException();
    if (response.statusCode != 200) {
      throw OffUnavailableException('Open Food Facts error ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    final hits = (body is Map ? body['hits'] : null) as List? ?? const [];
    return [
      for (final hit in hits.whereType<Map<String, dynamic>>()) ?parseHit(hit),
    ];
  }

  void _checkRateLimit() {
    final now = _clock();
    _recentRequests.removeWhere(
      (t) => now.difference(t) >= const Duration(minutes: 1),
    );
    if (_recentRequests.length >= OFF_SEARCH_LIMIT_PER_MINUTE) {
      throw const OffRateLimitedException();
    }
    _recentRequests.add(now);
  }
}

double? _num(Object? v) {
  final d = switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s),
    _ => null,
  };
  return d == null || d.isNaN || d.isInfinite || d < 0 ? null : d;
}

/// Maps one search hit to a cacheable food; null if it has no name or energy.
FoodsCompanion? parseHit(Map<String, dynamic> hit) {
  final code = hit['code']?.toString();
  final name = (hit['product_name'] as Object?)?.toString().trim() ?? '';
  final n = hit['nutriments'];
  if (code == null || name.isEmpty || n is! Map) return null;

  final kcal = _num(n['energy-kcal_100g']) ??
      _kjToKcal(_num(n['energy-kj_100g'])) ??
      _kjToKcal(_num(n['energy_100g']));
  if (kcal == null) return null;

  final brands = hit['brands'];
  final brand = switch (brands) {
    final List l when l.isNotEmpty => l.first.toString(),
    final String s when s.trim().isNotEmpty => s.split(',').first.trim(),
    _ => null,
  };
  final sodiumG = _num(n['sodium_100g']);

  return FoodsCompanion.insert(
    source: 'off',
    sourceId: Value(code),
    name: name,
    brand: Value(brand),
    servingG: Value(_positive(_num(hit['serving_quantity']))),
    kcal: kcal,
    proteinG: Value(_num(n['proteins_100g'])),
    carbsG: Value(_num(n['carbohydrates_100g'])),
    sugarG: Value(_num(n['sugars_100g'])),
    fiberG: Value(_num(n['fiber_100g'])),
    fatG: Value(_num(n['fat_100g'])),
    satFatG: Value(_num(n['saturated-fat_100g'])),
    sodiumMg: Value(sodiumG == null ? null : sodiumG * 1000),
  );
}

double? _kjToKcal(double? kj) => kj == null ? null : kj / 4.184;
double? _positive(double? v) => v == null || v <= 0 ? null : v;
