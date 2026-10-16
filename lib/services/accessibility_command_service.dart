import '../providers/accessibility_provider.dart';

class AccessibilityCommandResult {
  final String spokenText;
  final bool exit; // true when the user wants to leave the menu

  AccessibilityCommandResult(this.spokenText, {this.exit = false});
}

/// Interprets spoken commands inside the Pengaturan Aksesibilitas screen.
/// Every setting on that screen (ukuran teks, kontras, kecepatan suara,
/// TalkBack) can be changed purely by voice - the visible buttons/switches
/// are only there as a fallback for sighted users, the screen itself is
/// driven from what is said, not from what is tapped.
class AccessibilityVoiceController {
  static const String introText =
      'Anda berada di menu pengaturan aksesibilitas. '
      'Sebutkan ukuran teks normal, besar, atau sangat besar. '
      'Sebutkan kontras normal atau tinggi. '
      'Sebutkan kecepatan suara lambat, normal, atau cepat. '
      'Sebutkan talkback aktif atau nonaktif. '
      'Sebutkan bantuan untuk mendengar pilihan ini lagi, '
      'atau sebutkan kembali untuk kembali ke beranda.';

  Future<AccessibilityCommandResult> process(
    String rawText,
    AccessibilityProvider provider,
  ) async {
    final text = rawText.toLowerCase().trim();

    if (text.isEmpty) {
      return AccessibilityCommandResult(
        'Maaf, saya tidak mendengar apa pun. Silakan ulangi perintah Anda.',
      );
    }

    if (_matches(text, ['kembali', 'selesai', 'keluar', 'tutup', 'beranda'])) {
      return AccessibilityCommandResult(
        'Kembali ke menu utama.',
        exit: true,
      );
    }

    if (_matches(text, ['bantuan', 'opsi', 'pilihan', 'tolong'])) {
      return AccessibilityCommandResult(introText);
    }

    if (text.contains('ukuran teks') ||
        text.contains('ukuran tulisan') ||
        text.contains('ukuran huruf')) {
      // Checked most-specific-first: "sangat besar" also contains "besar".
      if (text.contains('sangat besar')) {
        await provider.setTextSize(TextSizeOption.sangatBesar);
        return AccessibilityCommandResult('Ukuran teks diubah menjadi sangat besar.');
      }
      if (text.contains('besar')) {
        await provider.setTextSize(TextSizeOption.besar);
        return AccessibilityCommandResult('Ukuran teks diubah menjadi besar.');
      }
      if (text.contains('normal') || text.contains('kecil')) {
        await provider.setTextSize(TextSizeOption.normal);
        return AccessibilityCommandResult('Ukuran teks diubah menjadi normal.');
      }
      return AccessibilityCommandResult(
        'Sebutkan ukuran teks normal, besar, atau sangat besar.',
      );
    }

    if (text.contains('kontras')) {
      if (text.contains('tinggi')) {
        await provider.setContrast(ContrastOption.tinggi);
        return AccessibilityCommandResult('Kontras diubah menjadi tinggi.');
      }
      if (text.contains('normal')) {
        await provider.setContrast(ContrastOption.normal);
        return AccessibilityCommandResult('Kontras diubah menjadi normal.');
      }
      return AccessibilityCommandResult('Sebutkan kontras normal atau tinggi.');
    }

    if (text.contains('kecepatan') || text.contains('suara lebih')) {
      if (text.contains('lambat') || text.contains('pelan') || text.contains('turun')) {
        await provider.setSpeechRate(0.3);
        return AccessibilityCommandResult('Kecepatan suara diubah menjadi lambat.');
      }
      if (text.contains('cepat') || text.contains('naik')) {
        await provider.setSpeechRate(0.7);
        return AccessibilityCommandResult('Kecepatan suara diubah menjadi cepat.');
      }
      if (text.contains('normal')) {
        await provider.setSpeechRate(0.5);
        return AccessibilityCommandResult('Kecepatan suara diubah menjadi normal.');
      }
      return AccessibilityCommandResult(
        'Sebutkan kecepatan suara lambat, normal, atau cepat.',
      );
    }

    if (text.contains('talkback')) {
      if (text.contains('nonaktif') || text.contains('matikan') || text.contains('mati')) {
        await provider.setTalkBackHints(false);
        return AccessibilityCommandResult('TalkBack dinonaktifkan.');
      }
      if (text.contains('aktif') || text.contains('nyalakan') || text.contains('hidupkan')) {
        await provider.setTalkBackHints(true);
        return AccessibilityCommandResult('TalkBack diaktifkan.');
      }
      return AccessibilityCommandResult('Sebutkan talkback aktif atau nonaktif.');
    }

    return AccessibilityCommandResult(
      'Maaf, perintah "$rawText" tidak dikenali di menu aksesibilitas. '
      'Sebutkan bantuan untuk mendengar pilihan yang tersedia.',
    );
  }

  bool _matches(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }
}
