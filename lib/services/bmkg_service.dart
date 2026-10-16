import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/error_type.dart';
import 'location_service.dart';
import 'weather_service.dart';

class _Wilayah {
  final String id;
  final String name;
  _Wilayah(this.id, this.name);
}

/// Prakiraan cuaca dari data terbuka BMKG (api.bmkg.go.id/publik/
/// prakiraan-cuaca). API BMKG membutuhkan kode wilayah tingkat IV
/// (kelurahan/desa, mis. 31.71.03.1001), sehingga lokasi pengguna dari
/// [AddressDetail] dicocokkan lebih dulu ke daftar wilayah administrasi
/// (provinsi -> kota/kab -> kecamatan -> kelurahan/desa).
///
/// Catatan: sumber data tidak lagi ditampilkan pada kartu hasil.
class BmkgService {
  static const String _forecastUrl =
      'https://api.bmkg.go.id/publik/prakiraan-cuaca';
  static const String _wilayahBase =
      'https://emsifa.github.io/api-wilayah-indonesia/api';

  // Cache selama aplikasi berjalan agar tanya cuaca berikutnya cepat.
  static final Map<String, List<_Wilayah>> _wilayahCache = {};
  static final Map<String, String> _adm4Cache = {};

  Future<Map<String, dynamic>> _fetchForecast(AddressDetail address) async {
    final adm4 = await _resolveAdm4(address);

    final uri = Uri.parse('$_forecastUrl?adm4=$adm4');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw AppException(ErrorType.apiError);
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) throw AppException(ErrorType.apiError);
    return data;
  }

  String? _areaOf(Map<String, dynamic> data) {
    final lokasi = data['lokasi'];
    if (lokasi is Map) {
      final parts = [lokasi['desa'], lokasi['kecamatan']]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isNotEmpty) return parts.join(', ');
    }
    return null;
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Prakiraan satu hari penuh (tanggal waktu setempat lokasi). BMKG hanya
  /// menyediakan sekitar 3 hari ke depan; di luar itu melempar
  /// [AppException] agar pemanggil memakai sumber lain.
  Future<WeatherResult> getDailyWeather(
      AddressDetail address, DateTime date) async {
    final data = await _fetchForecast(address);
    final key = _ymd(date);
    final entries = _flattenEntries(data).where((e) {
      final local = e['local_datetime'];
      return local is String && local.trim().startsWith(key);
    }).toList();
    if (entries.isEmpty) throw AppException(ErrorType.apiError);

    final temps = entries.map((e) => e['t']).whereType<num>().toList();
    if (temps.isEmpty) throw AppException(ErrorType.apiError);
    final tMin = temps.reduce((a, b) => a < b ? a : b).toDouble();
    final tMax = temps.reduce((a, b) => a > b ? a : b).toDouble();
    final hums = entries.map((e) => e['hu']).whereType<num>().toList();
    final humidity = hums.isEmpty
        ? null
        : (hums.reduce((a, b) => a + b) / hums.length).round();

    bool isRain(Map<String, dynamic> e) {
      final d = (e['weather_desc'] ?? '').toString().toLowerCase();
      return d.contains('hujan') || d.contains('petir');
    }

    String mostCommon(List<Map<String, dynamic>> list) {
      final counts = <String, int>{};
      for (final e in list) {
        final d = (e['weather_desc'] ?? '').toString();
        if (d.isNotEmpty) counts[d] = (counts[d] ?? 0) + 1;
      }
      if (counts.isEmpty) throw AppException(ErrorType.apiError);
      return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    final rainy = entries.where(isRain).toList();
    final dry = entries.where((e) => !isRain(e)).toList();
    // Hujan di sedikitnya separuh waktu prakiraan -> cuaca hari itu "hujan";
    // bila hanya sebagian, tampilkan kondisi dominan + waktu hujannya.
    final desc = rainy.isNotEmpty && (rainy.length * 2 >= entries.length || dry.isEmpty)
        ? mostCommon(rainy)
        : mostCommon(dry);

    String? rainNote;
    if (rainy.isNotEmpty) {
      final parts = <String>[];
      bool anyIn(int from, int to) => rainy.any((e) {
            final local = (e['local_datetime'] ?? '').toString();
            final h = int.tryParse(
                local.length >= 13 ? local.substring(11, 13) : '');
            return h != null && h >= from && h < to;
          });
      if (anyIn(5, 11)) parts.add('pagi');
      if (anyIn(11, 15)) parts.add('siang');
      if (anyIn(15, 18)) parts.add('sore');
      if (anyIn(18, 24) || anyIn(0, 5)) parts.add('malam');
      if (parts.isNotEmpty) {
        rainNote = 'hujan diperkirakan pada ${parts.join(', ')} hari';
      }
    } else {
      rainNote = 'tidak ada hujan diperkirakan';
    }

    return WeatherResult(
      desc,
      (tMin + tMax) / 2,
      tempMinC: tMin,
      tempMaxC: tMax,
      humidity: humidity,
      rainNote: rainNote,
      source: 'BMKG',
      area: _areaOf(data),
    );
  }

  Future<WeatherResult> getCurrentWeather(AddressDetail address) async {
    final data = await _fetchForecast(address);

    final entries = _flattenEntries(data);
    if (entries.isEmpty) throw AppException(ErrorType.apiError);

    final now = DateTime.now().toUtc();
    Map<String, dynamic> best = entries.first;
    var bestDiff = const Duration(days: 365);
    for (final e in entries) {
      final t = _entryTimeUtc(e);
      if (t == null) continue;
      final diff = t.difference(now).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = e;
      }
    }

    final temp = best['t'];
    final desc = best['weather_desc'];
    if (temp is! num || desc is! String || desc.isEmpty) {
      throw AppException(ErrorType.apiError);
    }
    final hu = best['hu'];

    return WeatherResult(
      desc,
      temp.toDouble(),
      humidity: hu is num ? hu.round() : null,
      source: 'BMKG',
      area: _areaOf(data),
    );
  }

  /// `data[0].cuaca` berisi daftar hari, tiap hari berisi daftar prakiraan
  /// per 3 jam. Diratakan menjadi satu daftar.
  List<Map<String, dynamic>> _flattenEntries(Map<String, dynamic> data) {
    final list = data['data'];
    if (list is! List || list.isEmpty) return [];
    final first = list.first;
    if (first is! Map) return [];
    final days = first['cuaca'];
    if (days is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final day in days) {
      if (day is! List) continue;
      for (final e in day) {
        if (e is Map) out.add(e.cast<String, dynamic>());
      }
    }
    return out;
  }

  DateTime? _entryTimeUtc(Map<String, dynamic> e) {
    final utc = e['utc_datetime'];
    if (utc is String) {
      final t = DateTime.tryParse('${utc.trim().replaceFirst(' ', 'T')}Z');
      if (t != null) return t;
    }
    final local = e['local_datetime'];
    if (local is String) {
      return DateTime.tryParse(local.trim().replaceFirst(' ', 'T'))?.toUtc();
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Pencarian kode wilayah tingkat IV (adm4)
  // ---------------------------------------------------------------------

  Future<String> _resolveAdm4(AddressDetail a) async {
    final cacheKey = [a.provinsi, a.kotaRaw, ...a.districtCandidates, ...a.villageCandidates].join('|');
    final cached = _adm4Cache[cacheKey];
    if (cached != null) return cached;

    final provinces = await _list('provinces.json');
    final prov = _pick(provinces, [a.provinsi]);
    if (prov == null) throw AppException(ErrorType.apiError);

    final regencies = await _list('regencies/${prov.id}.json');
    final reg = _pick(
      regencies,
      [a.kotaRaw],
      preferPrefix: a.isKota ? 'KOTA' : 'KABUPATEN',
    );
    if (reg == null) throw AppException(ErrorType.apiError);

    final districts = await _list('districts/${reg.id}.json');
    final dist = _pick(districts, a.districtCandidates);
    if (dist == null) throw AppException(ErrorType.apiError);

    final villages = await _list('villages/${dist.id}.json');
    if (villages.isEmpty) throw AppException(ErrorType.apiError);
    // Bila kelurahan tidak cocok, pakai kelurahan pertama di kecamatan yang
    // sama: prakiraan BMKG antar kelurahan bertetangga hampir sama.
    final village = _pick(villages, a.villageCandidates) ?? villages.first;

    final adm4 = _formatAdm4(village.id);
    _adm4Cache[cacheKey] = adm4;
    return adm4;
  }

  /// "3171031001" -> "31.71.03.1001"
  String _formatAdm4(String id) {
    if (id.length < 10) throw AppException(ErrorType.apiError);
    return '${id.substring(0, 2)}.${id.substring(2, 4)}.'
        '${id.substring(4, 6)}.${id.substring(6)}';
  }

  Future<List<_Wilayah>> _list(String path) async {
    final cached = _wilayahCache[path];
    if (cached != null) return cached;

    final response = await http
        .get(Uri.parse('$_wilayahBase/$path'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw AppException(ErrorType.apiError);

    final raw = jsonDecode(utf8.decode(response.bodyBytes));
    if (raw is! List) throw AppException(ErrorType.apiError);
    final items = <_Wilayah>[
      for (final m in raw)
        if (m is Map && m['id'] != null && m['name'] is String)
          _Wilayah(m['id'].toString(), m['name'] as String),
    ];
    _wilayahCache[path] = items;
    return items;
  }

  static final RegExp _prefixRegex = RegExp(
    r'^(daerah khusus ibukota|daerah istimewa|daerah khusus|dki|di|kota administrasi|kabupaten|kab|kota|kelurahan|kecamatan|kec|desa)\s+',
  );

  String _norm(String s) {
    var t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.replaceFirst(_prefixRegex, '');
  }

  _Wilayah? _pick(
    List<_Wilayah> items,
    List<String?> candidates, {
    String? preferPrefix,
  }) {
    final names = candidates.whereType<String>().toList();

    // 1) sama persis (setelah normalisasi)
    for (final c in names) {
      final n = _norm(c);
      if (n.isEmpty) continue;
      final hits = items.where((i) => _norm(i.name) == n).toList();
      if (hits.isEmpty) continue;
      if (hits.length > 1 && preferPrefix != null) {
        for (final h in hits) {
          if (h.name.toUpperCase().startsWith(preferPrefix)) return h;
        }
      }
      return hits.first;
    }

    // 2) salah satu mengandung yang lain
    for (final c in names) {
      final n = _norm(c);
      if (n.length < 4) continue;
      for (final i in items) {
        final m = _norm(i.name);
        if (m.isEmpty) continue;
        if (m.contains(n) || n.contains(m)) return i;
      }
    }
    return null;
  }
}
