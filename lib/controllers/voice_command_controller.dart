import 'package:flutter/foundation.dart';
import '../models/error_type.dart';
import '../services/command_service.dart';
import '../services/error_handler.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';

/// State aplikasi (SKPPL Tabel 4.23). Fetching Data digabung ke
/// [processing] pada tampilan (Bab 6.4).
enum VoiceState { idle, listening, processing, speaking, error }

/// VoiceCommandController (SKPPL 4.3): pengendali pusat alur dari perintah
/// suara hingga hasil.
class VoiceCommandController extends ChangeNotifier {
  final SpeechService _speech = SpeechService();
  final TtsService _tts = TtsService();
  final CommandService _commands = CommandService();
  final ErrorHandler _errors = ErrorHandler();

  VoiceState state = VoiceState.idle;
  String recognizedText = '';
  CommandResult? result;
  String errorMessage = '';
  String errorHint = '';

  /// True setelah hasil selesai dibacakan (kartu hasil tetap tampil).
  bool speakingDone = false;

  /// Kalimat yang diucapkan setelah jawaban selesai dibacakan.
  static const String newQuestionPrompt =
      'Ketuk layar untuk bertanya hal baru.';

  /// Jeda singkat agar audio TTS benar-benar berhenti sebelum mikrofon
  /// dibuka (mencegah mikrofon menangkap sisa suara TTS / status sibuk).
  static const Duration _audioSettleDelay = Duration(milliseconds: 500);

  /// Kalimat sambutan saat aplikasi dibuka (ditampilkan dan diucapkan).
  static const String welcomeMessage =
      'Selamat datang di DailyBrief. Temukan informasi dalam satu sentuhan. '
      'Ketuk untuk memulai pertanyaan.';

  int _session = 0; // membatalkan callback dari sesi lama
  bool _disposed = false;

  bool get isListening => state == VoiceState.listening;

  void _set(VoiceState s) {
    state = s;
    if (!_disposed) notifyListeners();
  }

  /// Membacakan sambutan saat layar utama dibuka. Dibatalkan otomatis bila
  /// pengguna sudah mengetuk layar.
  Future<void> greet() async {
    try {
      await _tts.speak(welcomeMessage);
    } catch (_) {
      // Sambutan tetap tampil secara visual.
    }
  }

  /// onMicPressed(): dijalankan saat tombol mikrofon / layar ditekan.
  Future<void> onMicPressed() async {
    if (state == VoiceState.processing) return;
    if (state == VoiceState.listening) {
      await cancel();
      return;
    }
    final session = ++_session;
    await _tts.stop();
    recognizedText = '';
    result = null;
    speakingDone = false;
    _set(VoiceState.listening);

    await Future.delayed(_audioSettleDelay);
    if (session != _session) return; // dibatalkan selama jeda

    await _speech.startListening(
      onResult: (text) {
        if (session != _session) return;
        _handleText(text, session);
      },
      onError: (type) {
        if (session != _session) return;
        _showError(type, session, speak: true);
      },
    );
  }

  Future<void> cancel() async {
    _session++;
    await _speech.cancel();
    await _tts.stop();
    _set(VoiceState.idle);
  }

  Future<void> _handleText(String text, int session) async {
    recognizedText = text;
    _set(VoiceState.processing);

    final r = await _commands.process(text);
    if (session != _session) return;

    if (r.isError) {
      await _showError(r.errorType ?? ErrorType.apiError, session, speak: true);
      return;
    }
    await _showResult(r, session);
  }

  /// showResult(text): menampilkan hasil dan membacakannya.
  Future<void> _showResult(CommandResult r, int session) async {
    result = r;
    _set(VoiceState.speaking);
    try {
      await _tts.speak(r.spokenText);
    } catch (_) {
      if (session != _session) return;
      // Skenario alternatif UC-08: suara gagal, tampilkan kesalahan visual.
      await _showError(ErrorType.ttsError, session, speak: false);
      return;
    }
    if (session != _session) return;

    // Jawaban selesai: layar bisa diketuk lagi untuk pertanyaan baru.
    speakingDone = true;
    if (!_disposed) notifyListeners();

    await Future.delayed(const Duration(milliseconds: 400));
    if (session != _session) return;
    try {
      await _tts.speak(newQuestionPrompt);
    } catch (_) {
      // Petunjuk tetap tampil secara visual.
    }
  }

  /// showError(message): menampilkan pesan dan membacakannya.
  Future<void> _showError(ErrorType type, int session,
      {required bool speak}) async {
    errorMessage = _errors.getMessage(type);
    errorHint = _errors.getHint(type);
    _set(VoiceState.error);
    if (!speak) return;
    try {
      await _tts.speak('$errorMessage. $errorHint.');
    } catch (_) {
      // Pesan tetap tampil secara visual.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _speech.cancel().catchError((_) {});
    _tts.stop().catchError((_) {});
    super.dispose();
  }
}
