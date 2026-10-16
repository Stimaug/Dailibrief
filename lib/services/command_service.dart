import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import '../models/error_type.dart';
import 'error_handler.dart';
import 'weather_service.dart';
import 'bmkg_service.dart';
import 'location_service.dart';

/// Enumerasi CommandType (SKPPL Tabel 4.21).
enum CommandType { hari, tanggal, waktu, cuaca, lokasi, tidakDikenali }

class CommandResult {
  final CommandType type;
  final String title; // judul tampilan, e.g. "Hari"
  final String spokenText; // full sentence spoken by TTS
  final String displayValue; // short value shown on screen, e.g. "Senin"
  final String? subValue; // optional second line, e.g. "Batam · 29°C"
  final IconData icon;
  final bool isError;
  final ErrorType? errorType;

  CommandResult({
    required this.type,
    required this.title,
    required this.spokenText,
    required this.displayValue,
    required this.icon,
    this.subValue,
    this.isError = false,
    this.errorType,
  });
}

/// Interprets the recognized text and produces the right response.
/// Covers: Mendapatkan informasi hari/tanggal/cuaca/lokasi, Menerima pesan
/// kesalahan. Supports relative day words (besok/kemarin/lusa) and named
/// place lookups ("lokasi Politeknik Negeri Batam"), not just "today" and
/// "my current location".
class CommandService {
  final WeatherService _weatherService = WeatherService();
  final BmkgService _bmkgService = BmkgService();
  final LocationService _locationService = LocationService();
  final ErrorHandler _errorHandler = ErrorHandler();

  /// Indonesian month names, used to recognize a specific date mentioned in
  /// a sentence (e.g. "tanggal 25 desember hari apa").
  static const Map<String, int> _monthNames = {
    'januari': 1,
    'februari': 2,
    'maret': 3,
    'april': 4,
    'mei': 5,
    'juni': 6,
    'juli': 7,
    'agustus': 8,
    'september': 9,
    'oktober': 10,
    'november': 11,
    'desember': 12,
  };

  /// Well-known fixed-date Indonesian holidays/observances, keyed by
  /// "dd-MM". Movable holidays (Idul Fitri, Nyepi, etc.) aren't included
  /// since they depend on a lunar/astronomical calendar that can't be
  /// computed locally.
  static const Map<String, String> _fixedHolidays = {
    '01-01': 'Tahun Baru Masehi',
    '01-05': 'Hari Buruh Internasional',
    '01-06': 'Hari Lahir Pancasila',
    '17-08': 'Hari Kemerdekaan Republik Indonesia',
    '28-10': 'Hari Sumpah Pemuda',
    '10-11': 'Hari Pahlawan',
    '25-12': 'Hari Natal',
  };

  static final RegExp _specificDateRegex = RegExp(
    r'(\d{1,2})\s+(januari|februari|maret|april|mei|juni|juli|agustus|september|oktober|november|desember)(?:\s+(\d{4}))?',
    caseSensitive: false,
  );

  Future<CommandResult> process(String rawText) async {
    final text = _wordsToDigits(
      rawText.toLowerCase().replaceAll("'", '').trim(),
    );

    if (text.isEmpty) {
      return _error(ErrorType.noSpeech);
    }

    // Cuaca diperiksa paling awal agar kalimat seperti "cuaca hari ini",
    // "cuaca besok di medan" atau "cuaca tanggal 10 desember" tidak
    // dijawab sebagai pertanyaan hari/tanggal.
    if (_isWeatherQuery(text)) {
      return _cuaca(text);
    }

    // Checked before the generic "tanggal"/"hari" handling below so a
    // sentence naming an explicit date - e.g. "tanggal 25 desember hari
    // apa" - resolves to that specific date and its weekday/holiday name,
    // instead of falling through to "today".
    final specificDate = _tanggalSpesifikJikaAda(text);
    if (specificDate != null) return specificDate;

    final offset = _dayOffsetFromText(text);

    if (_matches(text, ['hari'])) {
      return _hari(offset);
    }
    if (_matches(text, ['tanggal'])) {
      return _tanggal(offset);
    }
    if (_matches(text, ['waktu', 'jam', 'pukul'])) {
      return _waktu();
    }
    if (_matches(text, [
      'lokasi',
      'posisi',
      'alamat',
      'jalan apa',
      'dimana saya',
      'di mana saya',
      'saya dimana',
      'saya di mana',
    ])) {
      return _lokasi(text);
    }
    // "besok", "kemarin", or "lusa" said on their own (no explicit "hari"/
    // "tanggal" keyword) is still almost always a day question in everyday
    // speech, e.g. "besok apa" meaning "besok hari apa".
    if (offset != 0) {
      return _hari(offset);
    }

    return _error(ErrorType.unknownCommand);
  }

  bool _matches(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  /// Detects relative day words and returns how many days to offset from
  /// today. Checked from most specific to least specific so "kemarin lusa"
  /// isn't mistaken for plain "kemarin" or "lusa".
  int _dayOffsetFromText(String text) {
    if (text.contains('kemarin lusa')) return -2;
    if (text.contains('lusa')) return 2;
    if (text.contains('kemarin')) return -1;
    if (text.contains('besok')) return 1;
    return 0;
  }

  String _dayOffsetLabel(int offset) {
    switch (offset) {
      case 0:
        return 'Hari ini';
      case 1:
        return 'Besok';
      case -1:
        return 'Kemarin';
      case 2:
        return 'Lusa';
      case -2:
        return 'Kemarin lusa';
      default:
        return offset > 0 ? '$offset hari lagi' : '${-offset} hari yang lalu';
    }
  }

  CommandResult _hari(int offset) {
    final now = DateTime.now().add(Duration(days: offset));
    final dayName = intl.DateFormat('EEEE', 'id_ID').format(now);
    final label = _dayOffsetLabel(offset);
    return CommandResult(
      type: CommandType.hari,
      title: 'Hari',
      spokenText: '$label adalah hari $dayName.',
      displayValue: dayName,
      subValue: label,
      icon: Icons.calendar_today,
    );
  }

  CommandResult _tanggal(int offset) {
    final now = DateTime.now().add(Duration(days: offset));
    final formatted = intl.DateFormat('d MMMM yyyy', 'id_ID').format(now);
    final label = _dayOffsetLabel(offset);
    return CommandResult(
      type: CommandType.tanggal,
      title: 'Tanggal',
      spokenText: '$label tanggal $formatted.',
      displayValue: formatted,
      subValue: label,
      icon: Icons.event,
    );
  }

  /// Looks for a specific date mentioned in the sentence (day + Indonesian
  /// month name, optionally a year) and, if found, answers with which
  /// weekday that date falls/fell on, plus the holiday name if it's a
  /// well-known fixed-date one (e.g. 25 Desember -> Hari Natal). Returns
  /// null when no such date is present, so normal command matching
  /// continues.
  CommandResult? _tanggalSpesifikJikaAda(String text) {
    final match = _specificDateRegex.firstMatch(text);
    if (match == null) return null;

    final day = int.parse(match.group(1)!);
    final month = _monthNames[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    final yearGroup = match.group(3);
    final year = yearGroup != null ? int.parse(yearGroup) : DateTime.now().year;

    final date = DateTime(year, month, day);
    // DateTime "rolls over" invalid dates (e.g. 31 Februari -> 3 Maret)
    // instead of throwing, so check the day survived unchanged.
    if (date.day != day || date.month != month) {
      return _error(ErrorType.unknownCommand);
    }

    final dayName = intl.DateFormat('EEEE', 'id_ID').format(date);
    final formatted = intl.DateFormat('d MMMM yyyy', 'id_ID').format(date);
    final holidayKey =
        '${day.toString().padLeft(2, '0')}-${month.toString().padLeft(2, '0')}';
    final holidayName = _fixedHolidays[holidayKey];
    final holidaySentence =
        holidayName != null ? ' Tanggal tersebut adalah $holidayName.' : '';

    return CommandResult(
      type: CommandType.tanggal,
      title: 'Tanggal',
      spokenText: '$formatted jatuh pada hari $dayName.$holidaySentence',
      displayValue: '$dayName, $formatted',
      icon: Icons.event,
    );
  }

  CommandResult _waktu() {
    final now = DateTime.now();
    final formatted = intl.DateFormat('HH.mm', 'id_ID').format(now);
    return CommandResult(
      type: CommandType.waktu,
      title: 'Waktu',
      spokenText: 'Sekarang pukul $formatted.',
      displayValue: formatted,
      icon: Icons.access_time,
    );
  }

  // ---------------------------------------------------------------------
  // Cuaca: lokasi (saat ini / nama tempat) dan tanggal (hari ini, besok,
  // lusa, N hari lagi, nama hari, "10 desember", ...)
  // ---------------------------------------------------------------------

  static const List<String> _weatherKeywords = [
    'cuaca',
    'hujan',
    'gerimis',
    'mendung',
    'cerah',
    'panas',
    'suhu',
    'temperatur',
    'payung',
    'berawan',
    'prakiraan',
    'ramalan',
  ];

  bool _isWeatherQuery(String text) => _matches(text, _weatherKeywords);

  static const Map<String, int> _weekdays = {
    'senin': DateTime.monday,
    'selasa': DateTime.tuesday,
    'rabu': DateTime.wednesday,
    'kamis': DateTime.thursday,
    'jumat': DateTime.friday,
    'sabtu': DateTime.saturday,
    'minggu': DateTime.sunday,
  };

  static const Map<String, int> _numberUnits = {
    'satu': 1,
    'dua': 2,
    'tiga': 3,
    'empat': 4,
    'lima': 5,
    'enam': 6,
    'tujuh': 7,
    'delapan': 8,
    'sembilan': 9,
  };

  /// Pengenalan suara kadang menulis angka dengan huruf ("sepuluh
  /// desember", "dua puluh lima desember", "tiga hari lagi"). Diubah ke
  /// angka, tetapi hanya bila diikuti nama bulan / "hari" atau didahului
  /// "tanggal", agar kata lain tidak ikut berubah.
  String _wordsToDigits(String text) {
    final tokens = text.split(RegExp(r'\s+'));
    final out = <String>[];
    var i = 0;
    while (i < tokens.length) {
      int? value;
      var used = 0;
      final t = tokens[i];
      final next = i + 1 < tokens.length ? tokens[i + 1] : '';
      final next2 = i + 2 < tokens.length ? tokens[i + 2] : '';
      if (t == 'sepuluh') {
        value = 10;
        used = 1;
      } else if (t == 'sebelas') {
        value = 11;
        used = 1;
      } else if (_numberUnits.containsKey(t)) {
        final u = _numberUnits[t]!;
        if (next == 'belas') {
          value = 10 + u;
          used = 2;
        } else if (next == 'puluh') {
          final u2 = _numberUnits[next2];
          value = u * 10 + (u2 ?? 0);
          used = u2 != null ? 3 : 2;
        } else {
          value = u;
          used = 1;
        }
      }

      if (value != null) {
        final after = i + used < tokens.length ? tokens[i + used] : '';
        final before = i > 0 ? tokens[i - 1] : '';
        final ok = _monthNames.containsKey(after) ||
            after == 'hari' ||
            before == 'tanggal';
        if (ok) {
          out.add('$value');
          i += used;
          continue;
        }
      }
      out.add(t);
      i++;
    }
    return out.join(' ');
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Menentukan tanggal yang ditanyakan. Mengembalikan tanggal dan sisa
  /// kalimat (tanpa frasa tanggalnya) untuk mencari nama tempat.
  ({DateTime date, String rest}) _parseDate(String text, DateTime today) {
    final monthPattern = _monthNames.keys.join('|');

    // "10 desember", "tanggal 10 desember 2026"
    final specific = RegExp(
      '(?:tanggal\\s+)?(\\d{1,2})\\s+($monthPattern)(?:\\s+(\\d{4}))?',
    ).firstMatch(text);
    if (specific != null) {
      final day = int.parse(specific.group(1)!);
      final month = _monthNames[specific.group(2)!]!;
      final yearGroup = specific.group(3);
      var year = yearGroup != null ? int.parse(yearGroup) : today.year;
      var date = DateTime(year, month, day);
      if (yearGroup == null && date.isBefore(today)) {
        // Tanpa tahun dan tanggalnya sudah lewat: maksudnya tahun depan.
        date = DateTime(year + 1, month, day);
      }
      if (date.day == day && date.month == month) {
        return (
          date: date,
          rest: text.replaceFirst(specific.group(0)!, ' '),
        );
      }
      // Tanggal tidak ada (mis. 31 februari): abaikan, lanjut ke aturan lain.
    }

    // "3 hari lagi", "2 hari yang lalu"
    final relative = RegExp(
      r'(\d{1,3})\s+hari\s+(lagi|ke depan|lalu|yang lalu|kemarin)',
    ).firstMatch(text);
    if (relative != null) {
      final n = int.parse(relative.group(1)!);
      final back = !{'lagi', 'ke depan'}.contains(relative.group(2));
      return (
        date: today.add(Duration(days: back ? -n : n)),
        rest: text.replaceFirst(relative.group(0)!, ' '),
      );
    }

    final keywordOffsets = <String, int>{
      'kemarin lusa': -2,
      'lusa': 2,
      'kemarin': -1,
      'besok': 1,
      'minggu depan': 7,
    };
    for (final e in keywordOffsets.entries) {
      if (RegExp('\\b${e.key}\\b').hasMatch(text)) {
        return (
          date: today.add(Duration(days: e.value)),
          rest: text.replaceFirst(e.key, ' '),
        );
      }
    }

    // "hari rabu", "kamis depan" ("minggu" hanya bila didahului "hari").
    final weekday = RegExp(
      r'(?:hari\s+)?\b(senin|selasa|rabu|kamis|jumat|sabtu|minggu)\b(\s+depan)?',
    ).firstMatch(text);
    if (weekday != null) {
      final name = weekday.group(1)!;
      final hasHari = weekday.group(0)!.startsWith('hari');
      if (name != 'minggu' || hasHari) {
        var diff = (_weekdays[name]! - today.weekday) % 7;
        if (diff == 0 && weekday.group(2) != null) diff = 7;
        return (
          date: today.add(Duration(days: diff)),
          rest: text.replaceFirst(weekday.group(0)!, ' '),
        );
      }
    }

    return (date: today, rest: text);
  }

  static const Set<String> _weatherStopWords = {
    'cuaca', 'bagaimana', 'gimana', 'bagaimanakah', 'apakah', 'apa', 'kah',
    'ya', 'dong', 'tolong', 'tanya', 'mau', 'ingin', 'tahu', 'tau', 'kasih',
    'info', 'informasi', 'prakiraan', 'perkiraan', 'ramalan', 'nanti',
    'hari', 'ini', 'itu', 'besok', 'lusa', 'kemarin', 'lagi', 'tanggal',
    'tahun', 'depan', 'lalu', 'yang', 'akan', 'seperti', 'dan', 'sekarang',
    'saat', 'hujan', 'gerimis', 'mendung', 'cerah', 'panas', 'suhu',
    'temperatur', 'payung', 'berawan', 'atau', 'tidak', 'nggak', 'enggak',
    'gak', 'bakal', 'sih', 'deh', 'minggu', 'bulan', 'tgl',
  };

  static const Set<String> _selfWords = {
    'sini', 'saya', 'aku', 'kita', 'kami', 'anda', 'sekitar', 'situ',
    'lokasi', 'posisi', 'rumah', 'sekitarku', 'disini',
  };

  /// Nama tempat yang disebut di kalimat ("di medan", "untuk batam",
  /// "cuaca medan besok"), atau null bila yang dimaksud lokasi pengguna.
  String? _extractWeatherPlace(String rest) {
    var t = ' ${rest.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')} ';
    t = t.replaceAll(RegExp(r'\s+'), ' ');

    // Setelah kata depan ("di", "ke", "untuk", ...) itulah nama tempatnya.
    final prep = RegExp(
      r'\s(?:di|ke|untuk|buat|daerah|wilayah|kawasan)\s(.*)$',
    ).firstMatch(t);
    if (prep != null) t = ' ${prep.group(1)} ';

    final words = t
        .trim()
        .split(' ')
        .where((w) =>
            w.isNotEmpty &&
            !_weatherStopWords.contains(w) &&
            !_selfWords.contains(w) &&
            !RegExp(r'^\d+$').hasMatch(w))
        .toList();
    // "kota medan" / "kabupaten deli serdang" -> nama intinya saja.
    while (words.isNotEmpty &&
        {'kota', 'kabupaten', 'kab', 'provinsi'}.contains(words.first)) {
      words.removeAt(0);
    }
    final place = words.join(' ').trim();
    return place.isEmpty ? null : place;
  }

  /// "besok (Sabtu, 17 Oktober 2026)" / "pada hari Kamis, 10 Desember 2026".
  String _whenPhrase(int offset, DateTime date) {
    final full = intl.DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
    switch (offset) {
      case 0:
        return 'hari ini ($full)';
      case 1:
        return 'besok ($full)';
      case 2:
        return 'lusa ($full)';
      case -1:
        return 'kemarin ($full)';
      default:
        return 'pada hari $full';
    }
  }

  String _weatherTitle(int offset, DateTime date) {
    switch (offset) {
      case 0:
        return 'Cuaca Hari Ini';
      case 1:
        return 'Cuaca Besok';
      case 2:
        return 'Cuaca Lusa';
      case -1:
        return 'Cuaca Kemarin';
      default:
        return 'Cuaca ${intl.DateFormat('d MMMM yyyy', 'id_ID').format(date)}';
    }
  }

  Future<CommandResult> _cuaca(String text) async {
    try {
      final today = _dateOnly(DateTime.now());
      final parsed = _parseDate(text, today);
      final date = parsed.date;
      final offset = (date.difference(today).inHours / 24).round();
      final placeQuery = _extractWeatherPlace(parsed.rest);

      // 1) Lokasi: nama tempat yang disebut, atau GPS pengguna.
      double lat, lon;
      AddressDetail? address;
      String placeLabel;
      if (placeQuery != null) {
        final place = await _locationService.findPlace(placeQuery);
        lat = place.latitude;
        lon = place.longitude;
        address = place.address;
        placeLabel = place.name ?? _capitalize(placeQuery);
      } else {
        final loc = await _locationService.getCurrentLocation();
        lat = loc.latitude;
        lon = loc.longitude;
        address = loc.address;
        placeLabel = loc.cityName;
      }
      // BMKG butuh kelurahan/desa; nama kota saja (mis. "Medan") belum cukup.
      final canUseBmkg = address != null &&
          address.provinsi != null &&
          address.villageCandidates.isNotEmpty;

      // 2) Data cuaca sesuai tanggal.
      WeatherResult weather;
      if (offset == 0) {
        // Hari ini: kondisi saat ini (BMKG, cadangan Open-Meteo).
        weather = await _currentWeather(lat, lon, address, canUseBmkg);
      } else if (offset > WeatherService.maxForecastDays) {
        // Terlalu jauh untuk diprakirakan: rata-rata historis.
        weather = await _weatherService.getClimatology(
            latitude: lat, longitude: lon, date: date);
      } else {
        weather = await _dailyWeather(
            lat, lon, date, offset, address, canUseBmkg);
      }

      // 3) Susun jawaban.
      final place = placeQuery == null ? (weather.area ?? placeLabel) : placeLabel;
      final title = _weatherTitle(offset, date);

      if (offset == 0) {
        final intro = 'Cuaca saat ini di $place';
        return CommandResult(
          type: CommandType.cuaca,
          title: title,
          spokenText: '$intro adalah ${weather.spoken}.',
          displayValue: weather.description,
          subValue: '$place · ${weather.shortTemp}',
          icon: Icons.cloud,
        );
      }

      final when = _whenPhrase(offset, date);
      final dateShort = intl.DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);

      if (weather.isClimatology) {
        final years = weather.climatologyYears ?? 5;
        final rain = weather.rainNote != null ? ' dan ${weather.rainNote}' : '';
        return CommandResult(
          type: CommandType.cuaca,
          title: title,
          spokenText:
              'Prakiraan cuaca baru tersedia sampai ${WeatherService.maxForecastDays + 1} '
              'hari ke depan, jadi cuaca $when di $place belum bisa diprakirakan. '
              'Berdasarkan data $years tahun terakhir di sekitar tanggal itu, '
              'biasanya suhu ${weather.spokenTemp}$rain.',
          displayValue: weather.description,
          subValue: '$place · ${weather.shortTemp}\n'
              '$dateShort\n'
              'Rata-rata $years tahun terakhir, bukan prakiraan',
          icon: Icons.cloud,
        );
      }

      final isPast = offset < 0;
      final intro =
          isPast ? 'Cuaca $when di $place' : 'Prakiraan cuaca $when di $place';
      final verb = isPast ? 'tercatat' : 'adalah';
      final rain = weather.rainNote != null ? ', ${weather.rainNote}' : '';
      return CommandResult(
        type: CommandType.cuaca,
        title: title,
        spokenText:
            '$intro $verb ${weather.description.toLowerCase()}, suhu ${weather.spokenTemp}$rain.',
        displayValue: weather.description,
        subValue: '$place · ${weather.shortTemp}\n'
            '${weather.rainNote != null ? '${_capitalize1(weather.rainNote!)}\n' : ''}'
            '$dateShort',
        icon: Icons.cloud,
      );
    } catch (e) {
      return _error(_errorHandler.classify(e));
    }
  }

  Future<WeatherResult> _currentWeather(
    double lat,
    double lon,
    AddressDetail? address,
    bool canUseBmkg,
  ) async {
    if (canUseBmkg) {
      try {
        return await _bmkgService.getCurrentWeather(address!);
      } catch (_) {
        // jatuh ke Open-Meteo
      }
    }
    return _weatherService.getCurrentWeather(latitude: lat, longitude: lon);
  }

  Future<WeatherResult> _dailyWeather(
    double lat,
    double lon,
    DateTime date,
    int offset,
    AddressDetail? address,
    bool canUseBmkg,
  ) async {
    // BMKG menyediakan sekitar 3 hari ke depan per kelurahan/desa.
    if (canUseBmkg && offset >= 0 && offset <= 3) {
      try {
        return await _bmkgService.getDailyWeather(address!, date);
      } catch (_) {
        // jatuh ke Open-Meteo
      }
    }
    return _weatherService.getDailyWeather(
      latitude: lat,
      longitude: lon,
      date: date,
      archive: offset < -WeatherService.maxPastDays,
    );
  }

  String _capitalize1(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Routes a location question either to the user's current position, or
  /// to a search for a named place mentioned in the sentence.
  Future<CommandResult> _lokasi(String text) async {
    if (_isSelfLocationQuery(text)) return _lokasiSaatIni();
    final placeName = _extractPlaceName(text);
    if (placeName == null || placeName.isEmpty) {
      return _lokasiSaatIni();
    }
    return _lokasiTempat(placeName);
  }

  /// Pertanyaan tentang posisi pengguna sendiri, mis. "jalan apa ini" atau
  /// "alamat saya", yang tidak boleh dianggap sebagai nama tempat.
  bool _isSelfLocationQuery(String text) {
    const phrases = [
      'jalan apa',
      'alamat saya',
      'alamat ini',
      'saya dimana',
      'saya di mana',
      'aku dimana',
      'aku di mana',
      'lokasi sekarang',
      'posisi sekarang',
      'sekarang dimana',
      'sekarang di mana',
      'sedang dimana',
      'sedang di mana',
      'lokasi saya',
      'posisi saya',
      'lokasi aku',
      'posisi aku',
      'lokasi saat ini',
      'posisi saat ini',
      'lokasi ini',
      'posisi ini',
    ];
    return phrases.any(text.contains);
  }

  /// Strips command/trigger words out of the sentence so whatever remains
  /// (if anything) is treated as the name of a place to look up. Returns
  /// null when nothing meaningful remains, meaning "current location".
  String? _extractPlaceName(String text) {
    var t = ' $text ';
    const triggerPhrases = [
      'di mana saya',
      'dimana saya',
      'di mana letak',
      'dimana letak',
      'di mana',
      'dimana',
      'lokasi saya',
      'posisi saya',
      'ada di mana',
      'berada di mana',
      'lokasi',
      'posisi',
      'alamat',
      'cari',
      'tolong',
      'kamu tahu',
      'kau tahu',
    ];
    for (final phrase in triggerPhrases) {
      t = t.replaceAll(' $phrase ', ' ');
    }

    // "ini"/"itu" are included so a question like "lokasi ini dimana"
    // ("where is this place") resolves to the current location instead of
    // treating the leftover word "ini" as a place name to search for.
    const selfWords = {
      'saya',
      'aku',
      'kita',
      'sini',
      'kami',
      'anda',
      'ini',
      'itu',
      // Kata penunjuk waktu/keadaan: "lokasi saya saat ini" tidak boleh
      // meninggalkan kata "saat" sebagai nama tempat.
      'saat',
      'sekarang',
      'sedang',
      'berada',
      'lagi',
      'di',
      'nih',
      'dong',
      'ya',
    };
    final tokens = t
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !selfWords.contains(w))
        .toList();

    final result = tokens.join(' ').trim();
    return result.isEmpty ? null : result;
  }

  Future<CommandResult> _lokasiSaatIni() async {
    try {
      final loc = await _locationService.getCurrentLocation();
      final address = loc.address;
      if (address == null) {
        // GPS ada, tetapi alamat tidak bisa diterjemahkan (mis. offline).
        return _error(ErrorType.apiError);
      }
      return CommandResult(
        type: CommandType.lokasi,
        title: 'Lokasi',
        spokenText: address.spokenCurrent,
        displayValue: address.displayMain,
        subValue: address.displaySub,
        icon: Icons.location_on,
      );
    } catch (e) {
      return _error(_errorHandler.classify(e));
    }
  }

  Future<CommandResult> _lokasiTempat(String placeName) async {
    try {
      final place = await _locationService.findPlace(placeName);
      final address = place.address;
      return CommandResult(
        type: CommandType.lokasi,
        title: 'Lokasi',
        spokenText:
            '${place.name ?? _capitalize(placeName)} berlokasi di ${place.description}.',
        displayValue: address.streetLine ?? address.displayMain,
        subValue: address.displaySub,
        icon: Icons.location_on,
      );
    } catch (e) {
      return _error(_errorHandler.classify(e));
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  CommandResult _error(ErrorType type) {
    final message = _errorHandler.getMessage(type);
    return CommandResult(
      type: CommandType.tidakDikenali,
      title: 'Kesalahan',
      spokenText: '$message. ${_errorHandler.getHint(type)}.',
      displayValue: message,
      icon: Icons.error_outline,
      isError: true,
      errorType: type,
    );
  }
}
