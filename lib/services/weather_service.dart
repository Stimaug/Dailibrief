import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/error_type.dart';

class WeatherResult {
  final String description; // e.g. "Berawan"
  final double temperatureC; // suhu saat ini, atau rata-rata untuk prakiraan harian
  final double? tempMinC; // hanya prakiraan harian
  final double? tempMaxC;
  final int? humidity; // persen, bila tersedia
  final String? rainNote; // mis. "peluang hujan 70 persen"
  final String source; // "BMKG" atau "Open-Meteo"
  final String? area; // nama wilayah dari sumber data, bila ada
  final bool isClimatology; // true = rata-rata historis, bukan prakiraan
  final int? climatologyYears;

  WeatherResult(
    this.description,
    this.temperatureC, {
    this.tempMinC,
    this.tempMaxC,
    this.humidity,
    this.rainNote,
    this.source = 'Open-Meteo',
    this.area,
    this.isClimatology = false,
    this.climatologyYears,
  });

  bool get hasRange => tempMinC != null && tempMaxC != null;

  /// "24 sampai 31 derajat celsius" atau "29 derajat celsius".
  String get spokenTemp => hasRange
      ? '${tempMinC!.round()} sampai ${tempMaxC!.round()} derajat celsius'
      : '${temperatureC.round()} derajat celsius';

  /// "24–31°C" atau "29°C".
  String get shortTemp => hasRange
      ? '${tempMinC!.round()}–${tempMaxC!.round()}°C'
      : '${temperatureC.round()}°C';

  String get spoken {
    final base = '$description, $spokenTemp';
    return humidity != null ? '$base, kelembapan $humidity persen' : base;
  }

  String get short => '$description, $shortTemp';
}

/// Open-Meteo (gratis, tanpa API key):
///  - cuaca saat ini (cadangan BMKG)
///  - prakiraan harian sampai 15 hari ke depan dan 90 hari ke belakang
///  - rata-rata historis (arsip 5 tahun) untuk tanggal yang terlalu jauh
///    untuk diprakirakan, mis. 10 Desember saat ini bulan Oktober.
/// Utama untuk 0-3 hari: lihat bmkg_service.dart.
/// Covers the use case: Mendapatkan informasi cuaca.
class WeatherService {
  /// Batas prakiraan Open-Meteo (hari dari hari ini).
  static const int maxForecastDays = 15;

  /// Batas data "past" pada API prakiraan; lebih lama memakai arsip.
  static const int maxPastDays = 90;

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<WeatherResult> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude&longitude=$longitude&current_weather=true',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw AppException(ErrorType.apiError);
    }
    final data = jsonDecode(response.body);
    final current = data['current_weather'];
    final double temp = (current['temperature'] as num).toDouble();
    final int code = (current['weathercode'] as num).toInt();
    return WeatherResult(_describeWeatherCode(code), temp);
  }

  /// Prakiraan (atau data aktual bila tanggal sudah lewat) satu hari.
  Future<WeatherResult> getDailyWeather({
    required double latitude,
    required double longitude,
    required DateTime date,
    bool archive = false,
  }) async {
    final d = _ymd(date);
    final uri = Uri.https(
      archive ? 'archive-api.open-meteo.com' : 'api.open-meteo.com',
      archive ? '/v1/archive' : '/v1/forecast',
      {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'daily': archive
            ? 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum'
            : 'weather_code,temperature_2m_max,temperature_2m_min,'
                'precipitation_probability_max,precipitation_sum',
        'timezone': 'auto',
        'start_date': d,
        'end_date': d,
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw AppException(ErrorType.apiError);

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final daily = data is Map ? data['daily'] : null;
    if (daily is! Map) throw AppException(ErrorType.apiError);

    num? at(String key) {
      final list = daily[key];
      if (list is List && list.isNotEmpty && list.first is num) {
        return list.first as num;
      }
      return null;
    }

    final tMax = at('temperature_2m_max');
    final tMin = at('temperature_2m_min');
    final code = at('weather_code');
    if (tMax == null || tMin == null || code == null) {
      throw AppException(ErrorType.apiError);
    }
    final prob = at('precipitation_probability_max');
    final sum = at('precipitation_sum');

    String? rainNote;
    if (prob != null) {
      rainNote = 'peluang hujan ${prob.round()} persen';
    } else if (sum != null) {
      rainNote = sum >= 1
          ? 'curah hujan sekitar ${sum.round()} milimeter'
          : 'tidak ada hujan berarti';
    }

    return WeatherResult(
      _describeWeatherCode(code.toInt()),
      (tMax.toDouble() + tMin.toDouble()) / 2,
      tempMinC: tMin.toDouble(),
      tempMaxC: tMax.toDouble(),
      rainNote: rainNote,
    );
  }

  /// Rata-rata historis untuk [date] (jendela +-3 hari) selama [years]
  /// tahun terakhir. Dipakai bila tanggal di luar jangkauan prakiraan.
  Future<WeatherResult> getClimatology({
    required double latitude,
    required double longitude,
    required DateTime date,
    int years = 5,
  }) async {
    final thisYear = DateTime.now().year;

    Future<List<List<num?>>> fetchYear(int year) async {
      try {
        final center = DateTime(year, date.month, date.day);
        final uri = Uri.https('archive-api.open-meteo.com', '/v1/archive', {
          'latitude': '$latitude',
          'longitude': '$longitude',
          'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum',
          'timezone': 'auto',
          'start_date': _ymd(center.subtract(const Duration(days: 3))),
          'end_date': _ymd(center.add(const Duration(days: 3))),
        });
        final response =
            await http.get(uri).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) return const [];
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final daily = data is Map ? data['daily'] : null;
        if (daily is! Map) return const [];
        final maxs = daily['temperature_2m_max'];
        final mins = daily['temperature_2m_min'];
        final rains = daily['precipitation_sum'];
        if (maxs is! List || mins is! List || rains is! List) return const [];
        final out = <List<num?>>[];
        for (var i = 0; i < maxs.length; i++) {
          final a = maxs[i], b = mins[i], c = rains[i];
          if (a is num && b is num) {
            out.add([a, b, c is num ? c : null]);
          }
        }
        return out;
      } catch (_) {
        return const [];
      }
    }

    final perYear = await Future.wait([
      for (var i = 1; i <= years; i++) fetchYear(thisYear - i),
    ]);
    final days = perYear.expand((e) => e).toList();
    if (days.length < 7) throw AppException(ErrorType.apiError);

    final yearsUsed = perYear.where((e) => e.isNotEmpty).length;
    final avgMax = days.map((e) => e[0]!).reduce((a, b) => a + b) / days.length;
    final avgMin = days.map((e) => e[1]!).reduce((a, b) => a + b) / days.length;
    final withRain = days.where((e) => e[2] != null).toList();
    final rainyPct = withRain.isEmpty
        ? null
        : (100 * withRain.where((e) => e[2]! >= 1).length / withRain.length)
            .round();

    String description;
    if (rainyPct == null) {
      description = 'Tidak ada data hujan';
    } else if (rainyPct >= 60) {
      description = 'Biasanya hujan';
    } else if (rainyPct >= 30) {
      description = 'Kadang hujan';
    } else {
      description = 'Biasanya kering';
    }

    return WeatherResult(
      description,
      (avgMax + avgMin) / 2,
      tempMinC: avgMin,
      tempMaxC: avgMax,
      rainNote: rainyPct == null
          ? null
          : 'hujan turun pada sekitar $rainyPct persen harinya',
      isClimatology: true,
      climatologyYears: yearsUsed,
    );
  }

  // WMO Weather interpretation codes -> simple Indonesian description.
  String _describeWeatherCode(int code) {
    if (code == 0) return 'Cerah';
    if (code == 1) return 'Cerah berawan';
    if (code == 2) return 'Berawan sebagian';
    if (code == 3) return 'Berawan';
    if (code >= 45 && code <= 48) return 'Berkabut';
    if (code >= 51 && code <= 57) return 'Gerimis';
    if (code == 61 || code == 66) return 'Hujan ringan';
    if (code == 63) return 'Hujan sedang';
    if (code == 65 || code == 67) return 'Hujan lebat';
    if (code >= 71 && code <= 77) return 'Salju';
    if (code == 80) return 'Hujan ringan';
    if (code == 81) return 'Hujan sedang';
    if (code == 82) return 'Hujan deras';
    if (code >= 95) return 'Badai petir';
    return 'Tidak diketahui';
  }
}
