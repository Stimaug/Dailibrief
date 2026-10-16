import 'package:flutter_tts/flutter_tts.dart';
import '../models/error_type.dart';

/// Membungkus flutter_tts. Mewujudkan F-07 Mendapatkan Informasi Melalui Suara.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> init({double rate = 0.5}) async {
    if (_ready) return;
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  /// Membacakan [text] dan selesai setelah pembacaan berakhir.
  /// Melempar AppException(ErrorType.ttsError) bila gagal diputar.
  Future<void> speak(String text) async {
    try {
      if (!_ready) await init();
      await _tts.stop();
      final result = await _tts.speak(text);
      if (result == 0) throw AppException(ErrorType.ttsError);
    } catch (_) {
      throw AppException(ErrorType.ttsError);
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
