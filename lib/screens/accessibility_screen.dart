import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/accessibility_provider.dart';
import '../services/accessibility_command_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';

/// Pengaturan Aksesibilitas.
/// Covers the use case: Mengatur aksesibilitas
/// (Ukuran Teks, Kontras, Kecepatan Suara, dukungan TalkBack, Tentang Aplikasi).
///
/// Every setting here is voice-driven: on open, the screen explains the
/// available spoken commands and starts listening in a loop - the user
/// says e.g. "ukuran teks besar" or "talkback nonaktif" and the setting
/// changes immediately, confirmed out loud. The on-screen buttons/switches
/// below still work by tap (useful for a sighted person helping out), but
/// they are not the primary way this screen is meant to be used, so the
/// visual layout is kept as plain as possible.
class AccessibilityScreen extends StatefulWidget {
  const AccessibilityScreen({super.key});

  @override
  State<AccessibilityScreen> createState() => _AccessibilityScreenState();
}

class _AccessibilityScreenState extends State<AccessibilityScreen> {
  final SpeechService _speechService = SpeechService();
  final TtsService _ttsService = TtsService();
  final AccessibilityVoiceController _controller = AccessibilityVoiceController();
  bool _leaving = false;
  // Guards against speech_to_text firing both onResult AND onDone for the
  // same listening round (it does, once recognition finishes) - without
  // this, a single spoken command could kick off two overlapping listen
  // loops.
  bool _gotResultThisRound = false;
  String _status = 'Menyiapkan...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    final accessibility = context.read<AccessibilityProvider>();
    await _ttsService.init(rate: accessibility.speechRate);
    await _ttsService.speak(AccessibilityVoiceController.introText);
    _listenLoop();
  }

  Future<void> _listenLoop() async {
    if (_leaving || !mounted) return;
    _gotResultThisRound = false;
    setState(() => _status = 'Mendengarkan perintah aksesibilitas...');
    await _speechService.startListening(
      onResult: _handleResult,
      onDone: () {
        // Nothing recognized this round (silence/timeout) - just keep
        // listening quietly rather than giving up, since this menu is
        // meant to stay voice-controlled the whole time it's open. If a
        // result already came in, _handleResult is already driving the
        // next round, so skip starting a second one here.
        if (!_gotResultThisRound && !_leaving && mounted) {
          Future.delayed(const Duration(milliseconds: 400), _listenLoop);
        }
      },
    );
  }

  Future<void> _handleResult(String text) async {
    if (_leaving || !mounted) return;
    _gotResultThisRound = true;
    setState(() => _status = 'Memproses...');
    final provider = context.read<AccessibilityProvider>();
    final result = await _controller.process(text, provider);
    // Speech rate may just have changed - re-apply it for the confirmation.
    await _ttsService.setRate(provider.speechRate);
    await _ttsService.speak(result.spokenText);

    if (result.exit) {
      _leaving = true;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    _listenLoop();
  }

  @override
  void dispose() {
    _leaving = true;
    _speechService.stop();
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AccessibilityProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Aksesibilitas')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.mic),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_status)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.format_size,
              title: 'Ukuran Teks',
              subtitle: _textSizeLabel(a.textSize),
              child: SegmentedButton<TextSizeOption>(
                segments: const [
                  ButtonSegment(
                      value: TextSizeOption.normal, label: Text('Normal')),
                  ButtonSegment(
                      value: TextSizeOption.besar, label: Text('Besar')),
                  ButtonSegment(
                      value: TextSizeOption.sangatBesar,
                      label: Text('Sangat Besar')),
                ],
                selected: {a.textSize},
                onSelectionChanged: (s) => context
                    .read<AccessibilityProvider>()
                    .setTextSize(s.first),
              ),
            ),
            _SectionCard(
              icon: Icons.contrast,
              title: 'Kontras',
              subtitle: a.contrast == ContrastOption.tinggi
                  ? 'Tinggi'
                  : 'Normal',
              child: SegmentedButton<ContrastOption>(
                segments: const [
                  ButtonSegment(
                      value: ContrastOption.normal, label: Text('Normal')),
                  ButtonSegment(
                      value: ContrastOption.tinggi, label: Text('Tinggi')),
                ],
                selected: {a.contrast},
                onSelectionChanged: (s) => context
                    .read<AccessibilityProvider>()
                    .setContrast(s.first),
              ),
            ),
            _SectionCard(
              icon: Icons.speed,
              title: 'Kecepatan Suara',
              subtitle: _speedLabel(a.speechRate),
              child: Slider(
                value: a.speechRate,
                min: 0.2,
                max: 0.8,
                divisions: 6,
                label: _speedLabel(a.speechRate),
                onChanged: (v) =>
                    context.read<AccessibilityProvider>().setSpeechRate(v),
              ),
            ),
            _SectionCard(
              icon: Icons.record_voice_over,
              title: 'TalkBack',
              subtitle: a.talkBackHintsEnabled ? 'Aktif' : 'Nonaktif',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktifkan label bantuan untuk TalkBack'),
                    value: a.talkBackHintsEnabled,
                    onChanged: (v) => context
                        .read<AccessibilityProvider>()
                        .setTalkBackHints(v),
                  ),
                  // Short plain-language explanation of what this toggle
                  // actually does, since it isn't obvious from its title.
                  const Text(
                    'TalkBack adalah pembaca layar bawaan Android untuk '
                    'pengguna tunanetra/low vision. Tombol ini menambahkan '
                    'label suara yang lebih deskriptif pada tombol-tombol '
                    'di aplikasi ini agar TalkBack membacakannya dengan '
                    'lebih jelas. Ini bukan tombol untuk menghidupkan/'
                    'mematikan TalkBack itu sendiri - itu diatur lewat '
                    'Pengaturan Aksesibilitas bawaan HP Anda.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
            const _SectionCard(
              icon: Icons.info_outline,
              title: 'Tentang Aplikasi',
              subtitle: 'DailyBrief',
              child: _AboutAppContent(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  _leaving = true;
                  Navigator.of(context).pop();
                },
                child: const Text('Kembali'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _textSizeLabel(TextSizeOption o) {
    switch (o) {
      case TextSizeOption.normal:
        return 'Normal';
      case TextSizeOption.besar:
        return 'Besar';
      case TextSizeOption.sangatBesar:
        return 'Sangat Besar';
    }
  }

  String _speedLabel(double v) {
    if (v <= 0.35) return 'Lambat';
    if (v >= 0.65) return 'Cepat';
    return 'Normal';
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AboutAppContent extends StatelessWidget {
  const _AboutAppContent();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'DailyBrief membantu pengguna, khususnya tunanetra, memperoleh '
      'informasi harian (hari, tanggal, waktu, cuaca, lokasi) secara mandiri '
      'melalui perintah suara.\nVersi 1.0.0',
    );
  }
}
