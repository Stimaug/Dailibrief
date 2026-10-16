import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/speech_service.dart';
import '../services/command_service.dart';
import '../services/tts_service.dart';
import '../providers/history_provider.dart';
import '../providers/accessibility_provider.dart';
import '../models/command_history_item.dart';
import 'result_screen.dart';
import 'accessibility_screen.dart';
import 'help_screen.dart';

/// Listening / Proses Voice Command.
/// Covers: Memberikan perintah melalui suara, Menerima pesan kesalahan
/// (when the microphone/recognizer isn't available).
class ListeningScreen extends StatefulWidget {
  const ListeningScreen({super.key});

  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen> {
  final SpeechService _speechService = SpeechService();
  final CommandService _commandService = CommandService();
  final TtsService _ttsService = TtsService();
  bool _processing = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  Future<void> _begin() async {
    final accessibility = context.read<AccessibilityProvider>();
    await _ttsService.init(rate: accessibility.speechRate);

    await _speechService.startListening(
      onResult: (text) => _handleResult(text),
      onDone: () {
        // If listening ended with no result at all (e.g. mic unavailable,
        // permission denied, or nothing understood), show an error.
        if (!_finished) {
          _handleResult('');
        }
      },
    );
  }

  Future<void> _handleResult(String recognizedText) async {
    if (_finished) return;
    _finished = true;
    setState(() => _processing = true);

    // "aksesibilitas" and "bantuan" are navigation words, not data
    // commands: saying them opens that menu directly instead of reading
    // back a spoken answer on the Result screen.
    final normalized = recognizedText.toLowerCase();
    if (_matchesAny(normalized, ['aksesibilitas'])) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AccessibilityScreen()),
      );
      return;
    }
    if (_matchesAny(normalized, ['bantuan', 'tolong', 'help'])) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HelpScreen()),
      );
      return;
    }

    final result = await _commandService.process(recognizedText);

    if (!mounted) return;

    context.read<HistoryProvider>().add(
          CommandHistoryItem(
            title: result.title,
            value: result.displayValue,
            timestamp: DateTime.now(),
            icon: result.icon,
            isError: result.isError,
          ),
        );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }

  bool _matchesAny(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(k));
  }

  Future<void> _cancel() async {
    await _speechService.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _speechService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF11151C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              _PulsingMic(active: !_processing),
              const SizedBox(height: 32),
              Text(
                _processing ? 'Memproses...' : 'Mendengarkan...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Silakan ucapkan perintah Anda',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.close, color: Colors.white),
                label: const Text('Batal', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingMic extends StatefulWidget {
  final bool active;
  const _PulsingMic({required this.active});

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = widget.active ? 1.0 + (_controller.value * 0.15) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF2563EB),
            ),
            child: const Icon(Icons.mic, size: 56, color: Colors.white),
          ),
        );
      },
    );
  }
}
