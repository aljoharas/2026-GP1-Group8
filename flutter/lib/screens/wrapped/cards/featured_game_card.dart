// A single featured game: Card 3 (your #1 game) and Card 5 (your top online
// game). The game's art fills the screen blurred, with a slow Ken Burns
// drift, and its cover floats in front like a poster.

import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

class FeaturedGameCard extends StatefulWidget implements WrappedCard {
  final String eyebrow;
  final WrappedGame game;

  /// The year's total, for the "of your year" share; null hides it.
  final double? totalHours;
  final WrappedPalette palette;
  final IconData icon;

  const FeaturedGameCard({
    super.key,
    required this.eyebrow,
    required this.game,
    this.totalHours,
    this.palette = WrappedPalette.topGame,
    this.icon = Icons.emoji_events_rounded,
  });

  String? get _backdrop => game.backgroundImage ?? game.coverImage;

  /// Portrait cover art when there is some, else the landscape background.
  String? get _poster => game.coverImage ?? game.backgroundImage;

  @override
  List<String> get imageUrls => {?_backdrop, ?_poster}.toList();

  @override
  State<FeaturedGameCard> createState() => _FeaturedGameCardState();
}

class _FeaturedGameCardState extends WrappedCardState<FeaturedGameCard> {
  static const _total = Duration(milliseconds: 1600);
  static final _posterIn = msInterval(0, 900, _total, curve: Curves.easeOutCubic);
  static final _eyebrowIn = msInterval(300, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(420, 500, _total, curve: Curves.easeOutCubic);
  static final _statsIn = msInterval(560, 500, _total, curve: Curves.easeOutCubic);
  static final _count = msInterval(560, 1000, _total, curve: Curves.easeOutCubic);

  late final _kenBurns = AnimationController(vsync: this, duration: WrappedKenBurns.period);
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 5));
  late final _posterMotion = Listenable.merge([entrance, _float]);

  @override
  Duration get entranceDuration => _total;

  @override
  List<AnimationController> get loops => [_kenBurns, _float];

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final palette = widget.palette;
    final portrait = game.coverImage != null;
    final share = shareOfYear(game.hours, widget.totalHours);

    final art = WrappedKenBurns(
      controller: _kenBurns,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.clamp),
        child: Opacity(opacity: 0.75, child: WrappedImage(widget._backdrop)),
      ),
    );

    final poster = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          const BoxShadow(color: Color(0x8C000000), blurRadius: 48, offset: Offset(0, 16)),
          BoxShadow(color: palette.accentColor.withValues(alpha: 0.35), blurRadius: 60, spreadRadius: -6),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.2),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
              stops: [0.0, 0.45],
            ),
          ),
          child: AspectRatio(aspectRatio: portrait ? 3 / 4 : 16 / 10, child: WrappedImage(widget._poster)),
        ),
      ),
    );

    final visual = Semantics(
      label: '${game.name}, ${formatHours(game.hours)} played',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
          child: Center(
            child: AnimatedBuilder(
              animation: _posterMotion,
              builder: (context, child) {
                final t = _posterIn.transform(entrance.value);
                final float = sin(2 * pi * _float.value) * 3 * t;
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..translateByDouble(0, 60 * (1 - t) + float, 0, 1)
                      ..rotateX(0.35 * (1 - t))
                      ..scaleByDouble(0.88 + 0.12 * t, 0.88 + 0.12 * t, 1, 1),
                    child: child,
                  ),
                );
              },
              child: poster,
            ),
          ),
        ),
      ),
    );

    final text = AnimatedBuilder(
      animation: entrance,
      builder: (context, _) {
        final t = entrance.value;
        final counted = game.hours * _count.transform(t);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            riseIn(
              _eyebrowIn.transform(t),
              WrappedEyebrow.zone(widget.eyebrow, color: palette.accentColor, icon: widget.icon),
            ),
            const SizedBox(height: 10),
            riseIn(_headlineIn.transform(t), WrappedHeadline(game.name.toUpperCase(), maxLines: 2, minFontSize: 32)),
            const SizedBox(height: 22),
            riseIn(
              _statsIn.transform(t),
              distance: 12,
              WrappedStatPairs(
                accent: palette.accentColor,
                stats: [
                  WrappedStat(
                    icon: Icons.timer_rounded,
                    label: kHoursPlayedLabel,
                    value: formatNumber(counted, decimals: hoursDecimals(game.hours)),
                  ),
                  if (share != null) WrappedStat(icon: Icons.pie_chart_rounded, label: kShareOfYearLabel, value: share),
                ],
              ),
            ),
          ],
        );
      },
    );

    return WrappedBackdrop(
      palette: palette,
      drift: ambient,
      glowOpacity: 0.55,
      behind: Stack(
        fit: StackFit.expand,
        children: [
          art,
          // Light under the chrome, strong under the text zone.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x66000000),
                  const Color(0x26000000),
                  palette.base.withValues(alpha: 0.8),
                  palette.base.withValues(alpha: 0.97),
                ],
                stops: const [0.0, 0.4, 0.66, 0.85],
              ),
            ),
          ),
        ],
      ),
      child: WrappedSplitLayout(visual: visual, text: text),
    );
  }
}
