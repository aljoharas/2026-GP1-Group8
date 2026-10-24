// Card 10: you vs your friends. Two hourglasses, you and your rival, pour at
// the same rate; each holds sand for its hours, so the one with fewer hours
// runs dry first and the leader keeps pouring. Each total counts up as its
// glass stops, then the winner's glass glows once.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _palette = WrappedPalette.friendsHours;
const _rivalSand = Color(0xFFCBD5E1);
const _pourStartMs = 200;

/// A full glass's pour; a glass with less sand stops sooner.
const _pourMs = 2800;
const _countMs = 600;
const _glowMs = 800;

/// The least sand a glass with any hours shows.
const _minFill = 0.06;

/// Each glass's final fill: hours ÷ the larger of the two, at least
/// [_minFill] when there are any hours.
(double, double) hourglassFills(double mine, double rivals) {
  final most = max(mine, rivals);
  double fill(double hours) => most <= 0 || hours <= 0 ? 0 : max(_minFill, hours / most);
  return (fill(mine), fill(rivals));
}

class FriendsHoursCard extends StatefulWidget implements WrappedCard {
  final WrappedFriendsHours stats;
  final WrappedLeaderboardEntry me;
  final WrappedLeaderboardEntry rival;

  const FriendsHoursCard({super.key, required this.stats, required this.me, required this.rival});

  @override
  List<String> get imageUrls => [?me.user.avatarUrl, ?rival.user.avatarUrl];

  @override
  State<FriendsHoursCard> createState() => _FriendsHoursCardState();
}

class _FriendsHoursCardState extends WrappedCardState<FriendsHoursCard> {
  static const _total = Duration(milliseconds: _pourStartMs + _pourMs + _countMs + _glowMs);
  static final _visualIn = msInterval(0, 400, _total, curve: Curves.easeOutCubic);
  static final _eyebrowIn = msInterval(300, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(_pourStartMs + _pourMs - 200, 450, _total, curve: Curves.easeOutCubic);
  static final _lineIn = msInterval(_pourStartMs + _pourMs - 80, 450, _total, curve: Curves.easeOutCubic);
  static final _statsIn = msInterval(_pourStartMs + _pourMs + 40, 450, _total, curve: Curves.easeOutCubic);

  @override
  Duration get entranceDuration => _total;

  int _stopMs(double fill) => _pourStartMs + (_pourMs * fill).round();

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final rival = widget.rival;
    final outcome = hoursOutcome(me.hours, rival.hours);
    final (myFill, rivalFill) = hourglassFills(me.hours, rival.hours);
    final glowStart = _stopMs(max(myFill, rivalFill)) + _countMs ~/ 2;
    final glow = msInterval(glowStart, _glowMs, _total);

    Widget side(WrappedLeaderboardEntry entry, double fill, bool winner, bool mine) {
      final counted = msInterval(_stopMs(fill), _countMs, _total, curve: Curves.easeOutCubic);
      return _Contender(
        user: entry.user,
        hours: entry.hours,
        fill: fill,
        mine: mine,
        entrance: entrance,
        visualIn: _visualIn,
        count: counted,
        glow: winner ? glow : null,
        totalMs: _total.inMilliseconds,
      );
    }

    final visual = Semantics(
      label: friendsHoursSemantics(rival.user, me.hours, rival.hours),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: side(me, myFill, outcome != HoursOutcome.loss, true)),
              const SizedBox(width: 20),
              Expanded(child: side(rival, rivalFill, outcome != HoursOutcome.win, false)),
            ],
          ),
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
              WrappedEyebrow.zone(kFriendsHoursEyebrow, color: _palette.accentColor, icon: Icons.groups_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(_headlineIn.transform(t), WrappedHeadline(friendsHoursHeadline(outcome, rival.user))),
            const SizedBox(height: 12),
            riseIn(
              _lineIn.transform(t),
              WrappedSupportingLine(friendsHoursLine(outcome, rival.user, me.hours, rival.hours)),
              distance: 12,
            ),
            const SizedBox(height: 22),
            riseIn(
              _statsIn.transform(t),
              distance: 12,
              WrappedStatPairs(
                accent: _palette.accentColor,
                stats: [
                  WrappedStat(
                    icon: Icons.leaderboard_rounded,
                    label: kYourRankLabel,
                    value: yourRankValue(widget.stats),
                  ),
                  WrappedStat(
                    icon: Icons.military_tech_rounded,
                    label: kFriendsBeatenLabel,
                    value: '${widget.stats.friendsBeaten}',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    return WrappedBackdrop(
      palette: _palette,
      drift: ambient,
      child: WrappedSplitLayout(
        visual: Stack(
          children: [
            Positioned.fill(child: WrappedHeroGlow(color: _palette.accentColor, strength: 0.14)),
            Positioned.fill(child: visual),
          ],
        ),
        text: text,
      ),
    );
  }
}

/// One side of the race: avatar, hourglass, name and hours.
class _Contender extends StatelessWidget {
  final WrappedUser user;
  final double hours;
  final double fill;
  final bool mine;
  final Animation<double> entrance;
  final Curve visualIn;
  final Curve count;
  final Curve? glow;
  final int totalMs;

  const _Contender({
    required this.user,
    required this.hours,
    required this.fill,
    required this.mine,
    required this.entrance,
    required this.visualIn,
    required this.count,
    required this.glow,
    required this.totalMs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sand = mine ? _palette.accentColor : _rivalSand;
    final nameStyle = theme.textTheme.titleSmall!.copyWith(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    final hoursStyle = theme.textTheme.headlineSmall!.copyWith(
      color: mine ? _palette.accentColor : Colors.white,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final decimals = hoursDecimals(hours);

    return AnimatedBuilder(
      animation: entrance,
      builder: (context, _) {
        final ms = entrance.value * totalMs;
        final pour = ((ms - _pourStartMs) / _pourMs).clamp(0.0, 1.0);
        final counted = count.transform(entrance.value);
        final appear = visualIn.transform(entrance.value);
        return Opacity(
          opacity: appear,
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: mine ? _palette.accentColor : Colors.white.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: WrappedAvatar(url: user.avatarUrl, name: user.username, size: 56, tint: sand),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 0.62,
                    child: CustomPaint(
                      painter: _HourglassPainter(
                        bottom: min(pour, fill),
                        top: fill - min(pour, fill),
                        pouring: pour > 0 && pour < fill,
                        phase: ms / 380,
                        sand: sand,
                        glow: glow == null ? 0 : sin(pi * glow!.transform(entrance.value)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                user.username ?? (mine ? 'You' : displayName(user)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
              const SizedBox(height: 2),
              Opacity(
                opacity: counted > 0 ? 1 : 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${formatNumber(hours * counted, decimals: decimals)} ${hoursUnit(hours)}',
                    maxLines: 1,
                    style: hoursStyle,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HourglassPainter extends CustomPainter {
  /// Sand in each bulb, as a fraction of a full bulb.
  final double top;
  final double bottom;
  final bool pouring;

  /// Drives the falling grains; one grain cycle per unit.
  final double phase;
  final Color sand;

  /// 0..1, a soft halo around the glass.
  final double glow;

  const _HourglassPainter({
    required this.top,
    required this.bottom,
    required this.pouring,
    required this.phase,
    required this.sand,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cap = h * 0.045;
    final y0 = cap + h * 0.008;
    final y1 = h - cap - h * 0.008;
    final yN = h / 2;
    final left = w * 0.13;
    final right = w * 0.87;
    final neck = w * 0.035;
    final upper = yN - y0;
    final lower = y1 - yN;

    final glass = Path()
      ..moveTo(left, y0)
      ..cubicTo(left, y0 + upper * 0.55, cx - neck, yN - upper * 0.35, cx - neck, yN)
      ..cubicTo(cx - neck, yN + lower * 0.35, left, y1 - lower * 0.55, left, y1)
      ..lineTo(right, y1)
      ..cubicTo(right, y1 - lower * 0.55, cx + neck, yN + lower * 0.35, cx + neck, yN)
      ..cubicTo(cx + neck, yN - upper * 0.35, right, y0 + upper * 0.55, right, y0)
      ..close();

    if (glow > 0) {
      canvas.drawPath(
        glass,
        Paint()
          ..color = sand.withValues(alpha: 0.6 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
    }
    canvas.drawPath(glass, Paint()..color = Colors.white.withValues(alpha: 0.05));

    final sandPaint = Paint()..color = sand;
    canvas.save();
    canvas.clipPath(glass);
    if (top > 0) {
      // Rests on the neck, with a dip where it drains.
      final surface = yN - (upper - 4) * top;
      final dip = min(8.0, (yN - surface) * 0.3);
      canvas.drawPath(
        Path()
          ..moveTo(0, surface)
          ..quadraticBezierTo(cx, surface + 2 * dip, w, surface)
          ..lineTo(w, yN + 1)
          ..lineTo(0, yN + 1)
          ..close(),
        sandPaint,
      );
    }
    var landing = y1;
    if (bottom > 0) {
      // A mound, highest under the stream.
      final surface = y1 - (lower - 4) * bottom;
      final mound = min(10.0, (y1 - surface) * 0.35);
      landing = surface - mound / 2;
      canvas.drawPath(
        Path()
          ..moveTo(0, surface + mound)
          ..quadraticBezierTo(cx, surface - mound, w, surface + mound)
          ..lineTo(w, y1)
          ..lineTo(0, y1)
          ..close(),
        sandPaint,
      );
    }
    if (pouring) {
      canvas.drawLine(
        Offset(cx, yN - 2),
        Offset(cx, landing),
        Paint()
          ..color = sand.withValues(alpha: 0.75)
          ..strokeWidth = 1.4,
      );
      const grains = 9;
      for (var i = 0; i < grains; i++) {
        final f = (phase + i / grains) % 1;
        final y = yN + f * (landing - yN);
        final x = cx + sin((phase + i) * 7) * 1.8 * f;
        canvas.drawCircle(Offset(x, y), 1.5, sandPaint);
      }
    }
    canvas.restore();

    canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.55),
    );
    // A glint down the upper bulb.
    canvas.drawLine(
      Offset(left + w * 0.08, y0 + upper * 0.14),
      Offset(left + w * 0.1, y0 + upper * 0.45),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.28),
    );

    final capPaint = Paint()..color = const Color(0xFFE2E8F0);
    final radius = Radius.circular(cap / 2);
    canvas.drawRRect(RRect.fromLTRBR(0, 0, w, cap, radius), capPaint);
    canvas.drawRRect(RRect.fromLTRBR(0, h - cap, w, h, radius), capPaint);
  }

  @override
  bool shouldRepaint(_HourglassPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.pouring != pouring ||
      old.phase != phase ||
      old.sand != sand ||
      old.glow != glow;
}
