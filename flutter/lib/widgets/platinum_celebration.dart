// Full-screen "Platinum unlocked" moment: confetti over a dimmed screen and a
// card with the Platinum trophy. Shown when the last achievement is ticked.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const platinumColor = Color(0xFFB9D7EA);
const _platinumDeep = Color(0xFF6E97B8);
const _surface = Color(0xFF16161E);
const _muted = Color(0xFF6B6B80);

Future<void> showPlatinumCelebration(
  BuildContext context, {
  required String gameName,
  required String trophyName,
  String? image,
}) {
  HapticFeedback.heavyImpact();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Platinum unlocked',
    barrierColor: Colors.black.withValues(alpha: 0.8),
    transitionDuration: const Duration(milliseconds: 350),
    transitionBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
    pageBuilder: (_, _, _) => PlatinumCelebration(gameName: gameName, trophyName: trophyName, image: image),
  );
}

/// The Platinum trophy badge: a glowing platinum disc with a trophy (or the
/// game's own Platinum icon when it has one).
class PlatinumBadge extends StatelessWidget {
  final double size;
  final String? image;
  final bool dimmed;
  const PlatinumBadge({super.key, this.size = 44, this.image, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Colors.white, platinumColor, _platinumDeep],
          stops: [0.0, 0.55, 1.0],
          center: Alignment(-0.3, -0.4),
        ),
        boxShadow: dimmed
            ? null
            : [BoxShadow(color: platinumColor.withValues(alpha: 0.6), blurRadius: size * 0.4, spreadRadius: size * 0.03)],
      ),
      child: Icon(Icons.emoji_events, size: size * 0.56, color: const Color(0xFF3B5A73)),
    );
    final badge = image == null
        ? disc
        : ClipOval(
            child: Image.network(image!, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => disc),
          );
    return dimmed ? Opacity(opacity: 0.45, child: badge) : badge;
  }
}

class PlatinumCelebration extends StatefulWidget {
  final String gameName;
  final String trophyName;
  final String? image;

  const PlatinumCelebration({super.key, required this.gameName, required this.trophyName, this.image});

  @override
  State<PlatinumCelebration> createState() => _PlatinumCelebrationState();
}

class _PlatinumCelebrationState extends State<PlatinumCelebration> with TickerProviderStateMixin {
  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4500))..forward();
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  final _particles = _Particle.burst(160, Random());

  @override
  void dispose() {
    _confetti.dispose();
    _pop.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: _pop, curve: Curves.elasticOut);
    final textIn = CurvedAnimation(parent: _pop, curve: const Interval(0.3, 1.0, curve: Curves.easeOut));

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _confetti,
              builder: (_, _) => CustomPaint(painter: _ConfettiPainter(_particles, _confetti.value)),
            ),
          ),
        ),
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              key: const Key('platinum-celebration'),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: platinumColor.withValues(alpha: 0.35)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _glow,
                    builder: (_, child) => Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: platinumColor.withValues(alpha: 0.25 + 0.35 * _glow.value),
                            blurRadius: 30 + 20 * _glow.value,
                            spreadRadius: 4 + 6 * _glow.value,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    child: ScaleTransition(scale: scale, child: PlatinumBadge(size: 96, image: widget.image)),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: textIn,
                    child: Column(
                      children: [
                        const Text(
                          'PLATINUM UNLOCKED',
                          style: TextStyle(
                            color: platinumColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.trophyName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'You earned every achievement in ${widget.gameName}. Congratulations!',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted, fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: platinumColor,
                              foregroundColor: const Color(0xFF1B2B38),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Awesome!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _confettiColors = [
  platinumColor,
  Colors.white,
  Color(0xFF4ADE80),
  Color(0xFFFFD166),
  Color(0xFFFF6B9A),
  Color(0xFF7C9CFF),
];

/// One confetti piece, in units of the screen size so it fits any screen.
/// It is launched up and outward from just above the centre, then falls.
class _Particle {
  final double vx, vy; // launch velocity (screen widths / heights per run)
  final double spin, phase, sway;
  final double w, h;
  final double delay; // 0..0.25 of the run
  final Color color;

  _Particle(Random r)
      : vx = (r.nextDouble() - 0.5) * 1.6,
        vy = -(0.6 + r.nextDouble() * 0.9),
        spin = (r.nextDouble() - 0.5) * 30,
        phase = r.nextDouble() * pi * 2,
        sway = 0.01 + r.nextDouble() * 0.02,
        w = 6 + r.nextDouble() * 6,
        h = 3 + r.nextDouble() * 4,
        delay = r.nextDouble() * 0.25,
        color = _confettiColors[r.nextInt(_confettiColors.length)];

  static List<_Particle> burst(int n, Random r) => List.generate(n, (_) => _Particle(r));
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  _ConfettiPainter(this.particles, this.progress);

  static const _gravity = 2.6; // screen heights per run²

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final x = 0.5 + p.vx * t * 0.6 + sin(p.phase + t * 12) * p.sway;
      final y = 0.38 + p.vy * t + 0.5 * _gravity * t * t;
      if (y > 1.1) continue;
      final fade = t > 0.8 ? (1 - t) / 0.2 : 1.0;
      paint.color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.phase + p.spin * t);
      // Squash on one axis so pieces look like they flutter.
      canvas.scale(1, cos(p.phase + t * p.spin).abs() * 0.8 + 0.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h), const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

/// Small Platinum mark shown under game covers and next to names in the library.
class PlatinumCornerBadge extends StatelessWidget {
  final double size;
  const PlatinumCornerBadge({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Platinum earned',
        child: Container(
          key: const Key('platinum-corner-badge'),
          padding: const EdgeInsets.all(1.5),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xCC0E0E12)),
          child: PlatinumBadge(size: size),
        ),
      );
}
