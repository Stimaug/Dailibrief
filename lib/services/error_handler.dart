import 'dart:async';
import 'dart:io';
import '../models/error_type.dart';

/// ErrorHandler (SKPPL 4.11): menerjemahkan ErrorType menjadi pesan yang
/// mudah dipahami pengguna. (Pencatatan ke Firebase Crashlytics belum
/// dipasang; lihat catatan di README.)
class ErrorHandler {
  String getMessage(ErrorType type) {
    switch (type) {
      case ErrorType.micDenied:
        return 'Izin mikrofon ditolak';
      case ErrorType.noSpeech:
        return 'Tidak ada suara terdeteksi';
      case ErrorType.unknownCommand:
        return 'Perintah tidak dikenali';
      case ErrorType.gpsOff:
        return 'GPS tidak aktif';
      case ErrorType.noInternet:
        return 'Tidak ada koneksi internet';
      case ErrorType.apiError:
        return 'Informasi tidak dapat diambil';
      case ErrorType.ttsError:
        return 'Suara gagal diputar';
    }
  }

  /// Petunjuk singkat di bawah pesan kesalahan.
  String getHint(ErrorType type) {
    switch (type) {
      case ErrorType.micDenied:
        return 'Aktifkan izin mikrofon di pengaturan, lalu ketuk layar';
      case ErrorType.gpsOff:
        return 'Aktifkan GPS, lalu ketuk layar untuk mengulang';
      case ErrorType.noInternet:
        return 'Periksa koneksi, lalu ketuk layar untuk mengulang';
      case ErrorType.noSpeech:
        return 'Ketuk layar untuk mencoba lagi';
      default:
        return 'Ketuk layar untuk bertanya lagi';
    }
  }

  /// Mengubah exception apa pun menjadi ErrorType.
  ErrorType classify(Object error) {
    if (error is AppException) return error.type;
    if (error is SocketException || error is TimeoutException) {
      return ErrorType.noInternet;
    }
    return ErrorType.apiError;
  }
}
