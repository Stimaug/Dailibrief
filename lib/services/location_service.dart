import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../models/error_type.dart';

/// Alamat terperinci hasil geocoding (OpenStreetMap Nominatim), disusun
/// menurut hierarki administrasi Indonesia: jalan, kelurahan/desa,
/// kecamatan, kota/kabupaten, provinsi.
class AddressDetail {
  final String? nearName; // nama bangunan/tempat terdekat, bila ada
  final String? houseNumber;
  final String? road;
  final String? kelurahan;
  final String? kecamatan;
  final String? kotaRaw; // apa adanya, mis. "Batam"
  final bool isKota; // true = kota, false = kabupaten
  final String? provinsi;

  /// Asal data alamat: "OpenStreetMap" atau "Open-Meteo Geocoding".
  final String source;

  /// Kandidat nama untuk dicocokkan ke kode wilayah BMKG. Nominatim tidak
  /// selalu konsisten (suburb bisa berarti kelurahan atau kecamatan), jadi
  /// beberapa kandidat dicoba.
  final List<String> villageCandidates;
  final List<String> districtCandidates;

  const AddressDetail({
    this.nearName,
    this.houseNumber,
    this.road,
    this.kelurahan,
    this.kecamatan,
    this.kotaRaw,
    this.isKota = true,
    this.provinsi,
    this.source = 'OpenStreetMap',
    this.villageCandidates = const [],
    this.districtCandidates = const [],
  });

  factory AddressDetail.fromNominatim(Map<String, dynamic> data) {
    final a = (data['address'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    String? s(String key) {
      final v = a[key];
      return (v is String && v.trim().isNotEmpty) ? v.trim() : null;
    }

    final village = s('village');
    final suburb = s('suburb');
    final hamlet = s('hamlet');
    final cityDistrict = s('city_district');
    final municipality = s('municipality');
    final district = s('district');
    final city = s('city');
    final county = s('county') ?? s('regency');
    final town = s('town');

    final kotaRaw = city ?? county ?? town;
    final isKota = city != null ||
        (kotaRaw != null && kotaRaw.toLowerCase().startsWith('kota'));

    final road = s('road') ?? s('pedestrian') ?? s('residential');
    final topName = data['name'];
    String? nearName;
    if (topName is String && topName.trim().isNotEmpty) {
      final n = topName.trim();
      if (n.toLowerCase() != (road ?? '').toLowerCase()) nearName = n;
    }

    return AddressDetail(
      nearName: nearName,
      houseNumber: s('house_number'),
      road: road,
      kelurahan: village ?? suburb ?? hamlet,
      kecamatan: cityDistrict ??
          municipality ??
          district ??
          (village != null ? suburb : null),
      kotaRaw: kotaRaw,
      isKota: isKota,
      provinsi: s('state'),
      villageCandidates: [village, suburb, s('neighbourhood'), s('quarter'), hamlet]
          .whereType<String>()
          .toList(),
      districtCandidates: [cityDistrict, municipality, district, suburb, village]
          .whereType<String>()
          .toList(),
    );
  }

  static String _prefixed(String name, String prefix, List<String> known) {
    final lower = name.toLowerCase();
    for (final k in known) {
      if (lower.startsWith('$k ')) return name;
    }
    return '$prefix $name';
  }

  /// "Jl." -> "Jalan", "Gg." -> "Gang" agar enak dibacakan TTS.
  static String _expandRoad(String road) {
    return road
        .replaceFirst(RegExp(r'^Jl\.?\s+', caseSensitive: false), 'Jalan ')
        .replaceFirst(RegExp(r'^Gg\.?\s+', caseSensitive: false), 'Gang ');
  }

  String? get streetLine {
    if (road == null) return null;
    final r = _expandRoad(road!);
    return houseNumber != null ? '$r Nomor $houseNumber' : r;
  }

  String? get kelurahanLabel => kelurahan == null
      ? null
      : _prefixed(kelurahan!, isKota ? 'Kelurahan' : 'Desa',
          ['kelurahan', 'desa', 'kel.', 'kel']);

  String? get kecamatanLabel => kecamatan == null
      ? null
      : _prefixed(kecamatan!, 'Kecamatan', ['kecamatan', 'kec.', 'kec']);

  String? get kotaLabel => kotaRaw == null
      ? null
      : _prefixed(
          kotaRaw!, isKota ? 'Kota' : 'Kabupaten', ['kota', 'kabupaten', 'kab.']);

  List<String> get _regionParts =>
      [kelurahanLabel, kecamatanLabel, kotaLabel, provinsi]
          .whereType<String>()
          .toList();

  /// Kelurahan, kecamatan, kota, provinsi.
  String get regionLine => _regionParts.join(', ');

  /// Jalan (bila ada) diikuti wilayah administrasi.
  String get fullLine =>
      [streetLine, ..._regionParts].whereType<String>().join(', ');

  bool get isEmpty => streetLine == null && _regionParts.isEmpty;

  /// Nama kota singkat untuk keterangan cuaca, mis. "Batam".
  String get cityName => kotaRaw ?? provinsi ?? 'lokasi Anda';

  /// Kalimat untuk TTS saat ditanya "lokasi saya".
  String get spokenCurrent {
    final street = streetLine;
    if (street != null) {
      final near = nearName != null ? 'dekat $nearName, tepatnya ' : '';
      return 'Anda berada di ${near}sekitar $fullLine.';
    }
    return 'Nama jalan tidak terdeteksi. Anda berada di sekitar $regionLine.';
  }

  /// Nilai utama di kartu hasil.
  String get displayMain => streetLine ?? kelurahanLabel ?? cityName;

  /// Keterangan di bawah nilai utama.
  String? get displaySub {
    final parts = streetLine != null
        ? _regionParts
        : [kecamatanLabel, kotaLabel, provinsi].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }
}

class LocationResult {
  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// null bila pencarian alamat gagal (mis. Nominatim tidak terjangkau).
  final AddressDetail? address;

  LocationResult(
    this.latitude,
    this.longitude,
    this.address, {
    this.accuracyMeters = 0,
  });

  String get cityName => address?.cityName ?? 'lokasi Anda';
}

/// Hasil pencarian *tempat bernama*, mis. "Politeknik Negeri Batam".
class PlaceResult {
  final double latitude;
  final double longitude;
  final AddressDetail address;
  final String? name; // nama resmi tempat, bila ada
  PlaceResult(this.latitude, this.longitude, this.address, {this.name});

  /// Alamat lengkap sampai jalan, siap dibacakan.
  String get description =>
      address.isEmpty ? 'lokasi tidak diketahui' : address.fullLine;
}

/// Covers the use case: Mendapatkan informasi lokasi.
///  - lokasi saat ini ("lokasi saya", "saya di mana", "jalan apa ini")
///  - tempat bernama ("lokasi Politeknik Negeri Batam")
///
/// Posisi dari GPS (akurasi tinggi), alamat sampai nama jalan dari
/// OpenStreetMap Nominatim (zoom 18), semuanya gratis tanpa API key.
/// Pencarian nama tempat/kota: Nominatim, cadangan Open-Meteo Geocoding.
/// BMKG tidak menyediakan layanan
/// reverse-geocoding sampai jalan; BMKG dipakai untuk prakiraan cuaca
/// (lihat bmkg_service.dart) berdasarkan kelurahan/desa hasil lokasi ini.
class LocationService {
  static const String _userAgent = 'DailyBrief-App/1.0';

  Future<LocationResult> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw AppException(ErrorType.gpsOff);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw AppException(ErrorType.gpsOff);
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw AppException(ErrorType.gpsOff);
    }

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      // GPS lambat mengunci satelit: pakai posisi terakhir yang diketahui.
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) throw AppException(ErrorType.gpsOff);
      position = last;
    }

    final address =
        await _resolveAddress(position.latitude, position.longitude);
    return LocationResult(
      position.latitude,
      position.longitude,
      address,
      accuracyMeters: position.accuracy,
    );
  }

  /// Alamat dari OpenStreetMap Nominatim (gratis, tanpa API key), zoom 18
  /// agar sampai nama jalan. Diulang sekali bila gagal sesaat.
  Future<AddressDetail?> _resolveAddress(double lat, double lon) async {
    final first = await _reverseNominatim(lat, lon);
    if (first != null) return first;
    await Future.delayed(const Duration(milliseconds: 1200));
    return _reverseNominatim(lat, lon);
  }

  Future<AddressDetail?> _reverseNominatim(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=jsonv2&accept-language=id'
        '&zoom=18&addressdetails=1',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final detail = AddressDetail.fromNominatim(data);
      return detail.isEmpty ? null : detail;
    } catch (_) {
      return null;
    }
  }

  /// Mencari tempat bernama: Nominatim dulu (bisa sampai gedung/jalan),
  /// lalu Open-Meteo Geocoding (gratis, andal untuk nama kota) sebagai
  /// cadangan.
  Future<PlaceResult> findPlace(String query) async {
    try {
      return await _findPlaceNominatim(query);
    } on AppException {
      final r = await _findPlaceOpenMeteo(query);
      if (r != null) return r;
      rethrow;
    } catch (_) {
      final r = await _findPlaceOpenMeteo(query);
      if (r != null) return r;
      rethrow;
    }
  }

  Future<PlaceResult?> _findPlaceOpenMeteo(String query) async {
    try {
      final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': query,
        'count': '1',
        'language': 'id',
        'countryCode': 'ID',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final results = data is Map ? data['results'] : null;
      if (results is! List || results.isEmpty || results.first is! Map) {
        return null;
      }
      final r = results.first as Map;
      final lat = r['latitude'], lon = r['longitude'];
      if (lat is! num || lon is! num) return null;
      final name = r['name'] is String ? r['name'] as String : query;
      final admin1 = r['admin1'] is String ? r['admin1'] as String : null;
      return PlaceResult(
        lat.toDouble(),
        lon.toDouble(),
        AddressDetail(
          kotaRaw: name,
          provinsi: admin1,
          source: 'Open-Meteo Geocoding',
        ),
        name: name,
      );
    } catch (_) {
      return null;
    }
  }

  Future<PlaceResult> _findPlaceNominatim(String query) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeQueryComponent(query)}'
      '&format=jsonv2&limit=1&addressdetails=1&accept-language=id'
      '&countrycodes=id&dedupe=1',
    );
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw AppException(ErrorType.apiError);
    }

    final results = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    if (results.isEmpty) {
      throw AppException(ErrorType.apiError);
    }

    final place = results.first as Map<String, dynamic>;
    final lat = double.parse(place['lat'] as String);
    final lon = double.parse(place['lon'] as String);
    return PlaceResult(lat, lon, AddressDetail.fromNominatim(place));
  }
}
