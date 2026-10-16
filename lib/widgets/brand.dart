import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Ikon lingkaran konsentris berwarna biru (logo aplikasi).
class ConcentricLogo extends StatelessWidget {
  final double size;
  const ConcentricLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _circle(size, AppColors.ring1.withValues(alpha: 0.6)),
          _circle(size * 0.68, AppColors.ring1),
          _circle(size * 0.38, AppColors.primary),
        ],
      ),
    );
  }

  Widget _circle(double d, Color c) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );
}

/// Logo + nama aplikasi di bagian atas layar.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        ConcentricLogo(size: 28),
        SizedBox(width: 10),
        Text(
          'DailyBrief',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

/// Tombol mikrofon bulat biru dikelilingi lingkaran konsentris.
/// [scale] membesarkan lingkaran (state mendengarkan), [faded] memudarkan
/// tombol (state berbicara).
class MicButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final double ringScale;
  final bool faded;
  final Color color;
  final Color ringColor;

  const MicButton({
    super.key,
    this.onPressed,
    this.icon = Icons.mic,
    this.ringScale = 1.0,
    this.faded = false,
    this.color = AppColors.primary,
    this.ringColor = AppColors.ring1,
  });

  @override
  Widget build(BuildContext context) {
    final outer = 200.0 * ringScale;
    final middle = 150.0 * ringScale;
    return Opacity(
      opacity: faded ? 0.4 : 1,
      child: GestureDetector(
        onTap: onPressed,
        child: SizedBox(
          width: outer,
          height: outer,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _c(outer, ringColor.withValues(alpha: 0.45)),
              _c(middle, ringColor),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, size: 44, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _c(double d, Color c) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );
}
