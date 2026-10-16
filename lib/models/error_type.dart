/// Enumerasi ErrorType (SKPPL Tabel 4.22).
enum ErrorType {
  micDenied,
  noSpeech,
  unknownCommand,
  gpsOff,
  noInternet,
  apiError,
  ttsError,
}

/// Exception bertipe, dilempar oleh layanan agar controller tahu jenis
/// kesalahannya.
class AppException implements Exception {
  final ErrorType type;
  AppException(this.type);
  @override
  String toString() => 'AppException($type)';
}
