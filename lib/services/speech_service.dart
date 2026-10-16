import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import '../models/error_type.dart';

/// Membungkus speech_to_text (STT). Mewujudkan F-01 Memberikan Perintah Suara.
///
/// Catatan penting: di Android, status 'done' / 'notListening' sering datang
/// SEBELUM hasil akhir (finalResult) selesai diproses oleh mesin STT. Karena
/// itu layanan ini tidak langsung menyimpulkan "tidak ada suara", melainkan
/// menunggu [processingDelay] agar suara sempat diproses terlebih dahulu.
class SpeechService {
  /// Jeda tunggu setelah sesi berakhir sebelum disimpulkan "tidak ada suara".
  static const Duration processingDelay = Duration(milliseconds: 800);

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _finished = false; // hasil/error sudah dikirim untuk sesi ini
  String _lastWords = ''; // teks terakhir (parsial) sebagai cadangan
  int _session = 0;
  Timer? _processingTimer;
  void Function(String)? _onResult;
  void Function(ErrorType)? _onError;

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// Mendengarkan satu kali. [onResult] dipanggil dengan teks akhir;
  /// [onError] dipanggil dengan ErrorType.micDenied bila izin ditolak,
  /// ErrorType.noInternet bila gangguan jaringan, atau ErrorType.noSpeech
  /// bila (setelah jeda pemrosesan) memang tidak ada suara terdeteksi.
  Future<void> startListening({
    required void Function(String recognizedText) onResult,
    required void Function(ErrorType type) onError,
    String localeId = 'id_ID',
  }) async {
    final session = ++_session;
    _cancelProcessingTimer();
    _finished = false;
    _lastWords = '';
    _onResult = onResult;
    _onError = onError;

    if (!await _ensureMicPermission()) {
      _fail(ErrorType.micDenied);
      return;
    }
    if (session != _session) return;

    if (!_isInitialized) {
      _isInitialized = await _speech.initialize(
        onError: _handleEngineError,
        onStatus: _handleStatus,
      );
      if (!_isInitialized) {
        _fail(ErrorType.micDenied);
        return;
      }
    }
    if (session != _session) return;

    await _speech.listen(
      localeId: localeId,
      onResult: (result) {
        if (session != _session) return;
        final words = result.recognizedWords.trim();
        if (words.isNotEmpty) _lastWords = words;
        if (result.finalResult && words.isNotEmpty) _deliver(words);
      },
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 4),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true, // agar ada cadangan teks bila final terlambat
        cancelOnError: false,
      ),
    );
  }

  void _handleStatus(String status) {
    if (_finished) return;
    if (status == 'done' || status == 'notListening') {
      _scheduleConclusion();
    }
  }

  void _handleEngineError(dynamic error) {
    if (_finished) return;
    final msg = (error.errorMsg ?? '').toString();
    if (msg == 'error_permission') {
      _fail(ErrorType.micDenied);
    } else if (msg.startsWith('error_network') || msg == 'error_server') {
      _fail(ErrorType.noInternet);
    } else {
      // error_no_match, error_speech_timeout, dll: beri waktu dulu.
      _scheduleConclusion();
    }
  }

  /// Menunggu [processingDelay] sebelum menyimpulkan hasil sesi.
  void _scheduleConclusion() {
    if (_processingTimer?.isActive ?? false) return;
    final session = _session;
    _processingTimer = Timer(processingDelay, () {
      if (session != _session || _finished) return;
      // Status 'done' basi dari sesi lama: sesi baru masih mendengarkan.
      if (_speech.isListening) return;
      final words = _lastWords.trim();
      if (words.isNotEmpty) {
        _deliver(words); // final terlambat, pakai teks terakhir yang ada
      } else {
        _fail(ErrorType.noSpeech);
      }
    });
  }

  void _deliver(String words) {
    if (_finished) return;
    _finished = true;
    _cancelProcessingTimer();
    final cb = _onResult;
    _onResult = null;
    _onError = null;
    cb?.call(words);
  }

  void _fail(ErrorType type) {
    if (_finished) return;
    _finished = true;
    _cancelProcessingTimer();
    final cb = _onError;
    _onResult = null;
    _onError = null;
    cb?.call(type);
  }

  void _cancelProcessingTimer() {
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  Future<void> stop() async {
    _session++;
    _cancelProcessingTimer();
    _onResult = null;
    _onError = null;
    await _speech.stop();
  }

  Future<void> cancel() async {
    _session++;
    _cancelProcessingTimer();
    _onResult = null;
    _onError = null;
    await _speech.cancel();
  }
}
