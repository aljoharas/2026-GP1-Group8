// Card 1: total hours. A neon clock fast-forwards while its ring sweeps a full
// lap; the total starts counting up as the hands slow down.

import 'dart:math';

import 'package:flutter/material.dart';

import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _spinMs = 2000;
// Lands at 10:30; the hour hand turns 12× slower, like a real clock.
const _minuteTurns = 16.5;
const _palette = WrappedPalette.hours;

class TotalHoursCard extends StatefulWidget implements WrappedCard {
  final double hours;
  final int year;

  const TotalHoursCard({super.key, required this.hours, required this.year});

  @override
  List<String> get imageUrls => const [];

  @override
  State<TotalHoursCard> createState() => _TotalHoursCardState();
}

class _TotalHoursCardState extends WrappedCardState<TotalHoursCard> {
  static const _total = Duration(milliseconds: _spinMs + 200);
  static final _spin = msInterval(0, _spinMs, _total, curve: Curves.easeOutCubic);
  static final _clockIn = msInterval(0, 400, _total, curve: Curves.easeOutCubic);
  static final _eyebrowIn = msInterval(300, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(420, 500, _total, curve: Curves.easeOutCubic);
  // Counts while the hands decelerate, and lands with them.
  static final _count = msInterval(500, _spinMs - 500, _total, curve: Curves.easeOutCubic);
  static final _lineIn = msInterval(560, 500, _total, curve: Curves.easeOutCubic);

  @override
  Duration get entranceDuration => _total;

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;

    final visual = Semantics(
      label: 'You played ${formatHours(hours)} this year',
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Positioned.fill(child: WrappedHeroGlow(color: _palette.accentColor, strength: 0.16)),
            Center(
              child: LayoutBuilder(
                builder: (context, constraints) => SizedBox.square(
                  dimension: min(constraints.maxWidth - 48, constraints.maxHeight) * 0.92,
                  child: AnimatedBuilder(
                    animation: entrance,
                    builder: (context, _) {
                      final t = entrance.value;
                      final appear = _clockIn.transform(t);
                      return Opacity(
                        opacity: appear,
                        child: Transform.scale(
                          scale: 0.92 + 0.08 * appear,
                          child: CustomPaint(
                            painter: _ClockPainter(
                              minuteTurns: _minuteTurns * _spin.transform(t),
                              sweep: _spin.transform(t),
                              accent: _palette.accent,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final text = AnimatedBuilder(
      animation: entrance,
      builder: (context, _) {
        final t = entrance.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            riseIn(
              _eyebrowIn.transform(t),
              WrappedEyebrow.zone(kTotalHoursEyebrow, color: _palette.accentColor, icon: Icons.schedule_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(_headlineIn.transform(t), WrappedHeadline(totalHoursHeadline(hours * _count.transform(t), hours))),
            const SizedBox(height: 12),
            riseIn(_lineIn.transform(t), WrappedSupportingLine(totalHoursLine(hours, widget.year)), distance: 12),
          ],
        );
      },
    );

    return WrappedBackdrop(
      palette: _palette,
      drift: ambient,
      child: WrappedSplitLayout(visual: visual, text: text),
    );
  }
}

class _ClockPainter extends CustomPainter {
  final double minuteTurns;

  /// How much of the outer ring is lit, 0..1.
  final double sweep;
  final List<Color> accent;

  const _ClockPainter({required this.minuteTurns, required this.sweep, required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    const white = Colors.white;

    // Glassy face.
    canvas.drawCircle(
      centre,
      r * 0.92,
      Paint()
        ..shader = RadialGradient(
          colors: [white.withValues(alpha: 0.07), white.withValues(alpha: 0.015)],
        ).createShader(Rect.fromCircle(center: centre, radius: r)),
    );
    canvas.drawCircle(
      centre,
      r * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = white.withValues(alpha: 0.18),
    );

    // Unlit track, then the lit sweep with a soft glow under it.
    final ringRect = Rect.fromCircle(center: centre, radius: r * 0.98);
    final ringWidth = r * 0.035;
    canvas.drawArc(
      ringRect,
      0,
      2 * pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..color = white.withValues(alpha: 0.08),
    );
    if (sweep > 0) {
      // Starts at 12 o'clock, like the arc.
      final shader = SweepGradient(
        colors: [accent.last, accent.first],
        transform: const GradientRotation(-pi / 2),
      ).createShader(ringRect);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..strokeCap = StrokeCap.round
        ..shader = shader;
      canvas.drawArc(
        ringRect,
        -pi / 2,
        2 * pi * sweep,
        false,
        Paint.from(arc)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      canvas.drawArc(ringRect, -pi / 2, 2 * pi * sweep, false, arc);
    }

    // 60 ticks, the 12 hour marks longer and brighter.
    final tick = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 60; i++) {
      final hour = i % 5 == 0;
      final dir = _direction(i / 60);
      tick
        ..strokeWidth = r * (hour ? 0.022 : 0.008)
        ..color = white.withValues(alpha: hour ? 0.75 : 0.25);
      canvas.drawLine(centre + dir * r * (hour ? 0.76 : 0.82), centre + dir * r * 0.86, tick);
    }

    _hand(canvas, centre, minuteTurns / 12, r * 0.46, r * 0.05, accent.last, glow: null);
    _hand(canvas, centre, minuteTurns, r * 0.72, r * 0.025, accent.first, glow: accent.first);
    canvas.drawCircle(centre, r * 0.055, Paint()..color = accent.first);
    canvas.drawCircle(centre, r * 0.022, Paint()..color = const Color(0xFF0A0718));
  }

  // Unit vector for a fraction of a turn clockwise from 12 o'clock.
  static Offset _direction(double turns) {
    final angle = turns * 2 * pi - pi / 2;
    return Offset(cos(angle), sin(angle));
  }

  static void _hand(
    Canvas canvas,
    Offset centre,
    double turns,
    double length,
    double width,
    Color color, {
    required Color? glow,
  }) {
    final end = centre + _direction(turns) * length;
    if (glow != null) {
      canvas.drawLine(
        centre,
        end,
        Paint()
          ..color = glow.withValues(alpha: 0.7)
          ..strokeWidth = width * 2.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawLine(
      centre,
      end,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) => old.minuteTurns != minuteTurns || old.sweep != sweep || old.accent != accent;
}
