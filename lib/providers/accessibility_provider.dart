import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextSizeOption { normal, besar, sangatBesar }

enum ContrastOption { normal, tinggi }

/// Holds all accessibility preferences.
/// Covers the use case: Mengatur aksesibilitas
/// (Ukuran Teks, Kontras, Kecepatan Suara, dukungan TalkBack).
class AccessibilityProvider extends ChangeNotifier {
  TextSizeOption _textSize = TextSizeOption.normal;
  ContrastOption _contrast = ContrastOption.normal;
  double _speechRate = 0.5; // 0.0 (lambat) - 1.0 (cepat), passed to flutter_tts
  bool _talkBackHintsEnabled = true;

  TextSizeOption get textSize => _textSize;
  ContrastOption get contrast => _contrast;
  double get speechRate => _speechRate;
  bool get talkBackHintsEnabled => _talkBackHintsEnabled;

  double get textScaleFactor {
    switch (_textSize) {
      case TextSizeOption.normal:
        return 1.0;
      case TextSizeOption.besar:
        return 1.25;
      case TextSizeOption.sangatBesar:
        return 1.55;
    }
  }

  bool get isHighContrast => _contrast == ContrastOption.tinggi;

  AccessibilityProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _textSize = TextSizeOption.values[prefs.getInt('textSize') ?? 0];
    _contrast = ContrastOption.values[prefs.getInt('contrast') ?? 0];
    _speechRate = prefs.getDouble('speechRate') ?? 0.5;
    _talkBackHintsEnabled = prefs.getBool('talkBackHints') ?? true;
    notifyListeners();
  }

  Future<void> setTextSize(TextSizeOption value) async {
    _textSize = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('textSize', value.index);
  }

  Future<void> setContrast(ContrastOption value) async {
    _contrast = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contrast', value.index);
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speechRate', value);
  }

  Future<void> setTalkBackHints(bool value) async {
    _talkBackHintsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('talkBackHints', value);
  }
}
