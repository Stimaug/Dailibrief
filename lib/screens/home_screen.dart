import 'package:flutter/material.dart';
import '../controllers/voice_command_controller.dart';
import '../services/command_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';

/// Layar utama. Mewujudkan antarmuka Bab 6 sesuai state:
/// 6.2 Siap (idle), 6.3 Mendengarkan (listening), 6.4 Memproses (processing),
/// 6.5 Berbicara / Hasil (speaking), 6.6 Terjadi Kesalahan (error).
/// Seluruh layar dapat diketuk untuk memulai perintah suara.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final VoiceCommandController _c = VoiceCommandController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _c.greet());
  }

  void _onChange() {
    if (_c.state == VoiceState.listening || _c.state == VoiceState.processing) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _c.onMicPressed,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _c,
            builder: (context, _) => Column(
              children: [
                const SizedBox(height: 24),
                const BrandHeader(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey(_c.state),
                      child: _body(),
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

  Widget _body() {
    switch (_c.state) {
      case VoiceState.idle:
        return _idle();
      case VoiceState.listening:
        return _listening();
      case VoiceState.processing:
        return _processing();
      case VoiceState.speaking:
        return _speaking();
      case VoiceState.error:
        return _error();
    }
  }

  // 6.2 Siap Digunakan
  Widget _idle() => _centered(
        top: const _Title('Selamat datang di DailyBrief'),
        middle: MicButton(onPressed: _c.onMicPressed),
        bottom: const _Hint(
            'Temukan informasi dalam satu sentuhan.\nKetuk untuk memulai pertanyaan.'),
      );

  // 6.3 Mendengarkan
  Widget _listening() => _centered(
        middle: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => MicButton(
            onPressed: _c.onMicPressed,
            ringScale: 1.1 + _pulse.value * 0.15,
          ),
        ),
        top: const _Title('Mendengarkan...'),
        bottom: const _Hint('Silakan ucapkan perintah Anda'),
      );

  // 6.4 Memproses
  Widget _processing() => _centered(
        top: const _Title('Sedang Memproses...'),
        middle: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => MicButton(
            icon: _pulse.value < 0.5
                ? Icons.hourglass_top_rounded
                : Icons.hourglass_bottom_rounded,
            ringScale: 1.0 + _pulse.value * 0.08,
          ),
        ),
        bottom: const _Hint(
            'Mohon tunggu sebentar, sistem sedang mencari informasi untuk Anda'),
      );

  // 6.5 Berbicara / Hasil
  Widget _speaking() {
    final r = _c.result!;
    final done = _c.speakingDone;
    return Column(
      children: [
        const Spacer(flex: 2),
        _ResultCard(result: r),
        const SizedBox(height: 28),
        done
            ? const _Hint('Ketuk layar untuk bertanya hal baru')
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.volume_up_rounded,
                      size: 20, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text(
                    'Sedang berbicara...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
        const Spacer(flex: 2),
        MicButton(
          faded: !done,
          ringScale: 0.6,
          onPressed: done ? _c.onMicPressed : null,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // 6.6 Terjadi Kesalahan
  Widget _error() => Column(
        children: [
          const Spacer(flex: 2),
          Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.errorSoft,
            ),
            child: const Icon(Icons.mic_off_rounded,
                size: 52, color: AppColors.error),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _c.errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _c.errorHint,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.textMuted),
          ),
          const Spacer(flex: 2),
          MicButton(ringScale: 0.6, onPressed: _c.onMicPressed),
          const SizedBox(height: 24),
        ],
      );

  /// Susunan umum: judul/status di atas tombol, petunjuk di bawah layar.
  Widget _centered({
    required Widget top,
    required Widget middle,
    required Widget bottom,
  }) {
    return Column(
      children: [
        const Spacer(flex: 2),
        top,
        const SizedBox(height: 28),
        middle,
        const Spacer(flex: 2),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
          child: bottom,
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
      );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 15, color: AppColors.textMuted),
      );
}

/// Kartu hasil: judul jenis informasi, ikon, nilai utama, dan keterangan.
class _ResultCard extends StatelessWidget {
  final CommandResult result;
  const _ResultCard({required this.result});

  String get _label =>
      result.title.toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            _label,
            style: const TextStyle(
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primarySoft,
            ),
            child: Icon(result.icon, size: 34, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            result.displayValue,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          if (result.subValue != null) ...[
            const SizedBox(height: 6),
            Text(
              result.subValue!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
