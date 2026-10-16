import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/command_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../providers/accessibility_provider.dart';

/// Bantuan screen - lists the voice commands the user can say.
///
/// This screen never opens a sub-menu: as soon as it opens it reads
/// everything on the page out loud automatically, ending with "sebutkan
/// kembali untuk kembali ke halaman utama", then starts listening for that
/// word. Tapping anywhere on the screen (like the mic on the home screen)
/// also starts listening immediately - the user doesn't need to find a
/// precise button. Saying "kembali" returns to the home screen.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final TtsService _tts = TtsService();
  final SpeechService _speech = SpeechService();
  bool _leaving = false;
  bool _busy = false; // true while TTS is speaking, to avoid overlapping mic
  // Guards against speech_to_text firing both onResult AND onDone for the
  // same listening round.
  bool _gotResultThisRound = false;
  String _status = 'Membacakan bantuan...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakAllThenListen());
  }

  Future<void> _speakAllThenListen() async {
    if (_leaving || !mounted) return;
    _busy = true;
    setState(() => _status = 'Membacakan bantuan...');
    final accessibility = context.read<AccessibilityProvider>();
    await _tts.init(rate: accessibility.speechRate);
    await _tts.speak(
      'Halaman bantuan. Anda dapat mengatakan beberapa perintah berikut: '
      '${CommandService.availableCommands.join(", ")}. '
      'Sebutkan kembali untuk kembali ke halaman utama.',
    );
    _busy = false;
    if (!_leaving && mounted) _listen();
  }

  Future<void> _listen() async {
    if (_leaving || !mounted) return;
    _gotResultThisRound = false;
    setState(() => _status = 'Mendengarkan... sebutkan "kembali" untuk pulang');
    await _speech.startListening(
      onResult: _handleResult,
      onDone: () {
        if (!_gotResultThisRound && !_leaving && mounted) {
          Future.delayed(const Duration(milliseconds: 400), _listen);
        }
      },
    );
  }

  Future<void> _handleResult(String text) async {
    if (_leaving || !mounted) return;
    _gotResultThisRound = true;
    final normalized = text.toLowerCase().trim();

    if (_matchesAny(normalized, ['kembali', 'beranda', 'selesai', 'keluar'])) {
      _leaving = true;
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    // Anything else said here: a short reminder, then keep listening -
    // this page only understands "kembali", it doesn't act on other
    // commands.
    _busy = true;
    setState(() => _status = 'Memproses...');
    await _tts.speak('Sebutkan kembali untuk kembali ke halaman utama.');
    _busy = false;
    if (!_leaving && mounted) _listen();
  }

  bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  /// Acts just like tapping the mic on the home screen: tapping anywhere
  /// on this page (re)starts listening right away.
  void _tapToListen() {
    if (_leaving || _busy || _speech.isListening) return;
    _listen();
  }

  @override
  void dispose() {
    _leaving = true;
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tapToListen,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mic, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _status,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Anda dapat mengatakan beberapa perintah berikut:',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: CommandService.availableCommands
                        .map(
                          (c) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Icon(Icons.circle, size: 8),
                                ),
                                const SizedBox(width: 12),
                                // Expanded + softWrap lets long command
                                // labels wrap onto a second line instead of
                                // running off the right edge of the screen.
                                Expanded(
                                  child: Text(
                                    c,
                                    softWrap: true,
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                Text(
                  'Sebutkan "kembali" untuk kembali ke halaman utama.',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _speakAllThenListen,
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Dengarkan Lagi'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
