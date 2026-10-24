// Card 8: game status. Three bars (completed, still playing, paused) rise one
// after another, their counts ticking up on top; the bar that matches the
// user's player type is lit in the accent colour.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _palette = WrappedPalette.gameStatus;
const _barGapMs = 150;
const _barMs = 700;

/// Shortest bar for a non-zero count, as a fraction of the tallest.
const _minBar = 0.08;

enum StatusBar { completed, playing, paused }

/// The bar a player type is about, or null when it isn't about one.
StatusBar? highlightedBar(PlayerType? type) => switch (type) {
  PlayerType.theCloser || PlayerType.creditsChaser => StatusBar.completed,
  PlayerType.theJuggler => StatusBar.playing,
  PlayerType.saveAndQuit => StatusBar.paused,
  PlayerType.foreverInProgress || null => null,
};

class GameStatusCard extends StatefulWidget implements WrappedCard {
  final WrappedPlayStyle style;

  const GameStatusCard({super.key, required this.style});

  @override
  List<String> get imageUrls => const [];

  @override
  State<GameStatusCard> createState() => _GameStatusCardState();
}

class _GameStatusCardState extends WrappedCardState<GameStatusCard> {
  static const _total = Duration(milliseconds: 2 * _barGapMs + _barMs + 300);
  static final _bars = [
    for (var i = 0; i < 3; i++) msInterval(i * _barGapMs, _barMs, _total, curve: Curves.easeOutCubic),
  ];
  static final _barFade = [for (var i = 0; i < 3; i++) msInterval(i * _barGapMs, 200, _total)];
  static final _eyebrowIn = msInterval(300, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(420, 500, _total, curve: Curves.easeOutCubic);

  @override
  Duration get entranceDuration => _total;

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final counts = [style.finished, style.playing, style.paused];
    const labels = [kStatusCompleted, kStatusPlaying, kStatusPaused];
    final highlight = highlightedBar(style.type);
    final most = counts.reduce(max);

    final visual = Semantics(
      label: gameStatusSemantics(style),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AnimatedBuilder(
            animation: entrance,
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  Expanded(
                    child: Opacity(
                      opacity: _barFade[i].transform(entrance.value),
                      child: _Bar(
                        count: counts[i],
                        share: most == 0 || counts[i] == 0 ? 0 : max(_minBar, counts[i] / most),
                        progress: _bars[i].transform(entrance.value),
                        label: labels[i],
                        lit: highlight == StatusBar.values[i],
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
              WrappedEyebrow.zone(kGameStatusEyebrow, color: _palette.accentColor, icon: Icons.bar_chart_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(_headlineIn.transform(t), WrappedHeadline(gameStatusHeadline(style.total))),
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
            Positioned.fill(child: WrappedHeroGlow(color: _palette.accent.last, strength: 0.16)),
            Positioned.fill(child: visual),
          ],
        ),
        text: text,
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final int count;

  /// Height as a fraction of the tallest bar; 0 draws only a baseline.
  final double share;
  final double progress;
  final String label;
  final bool lit;

  const _Bar({
    required this.count,
    required this.share,
    required this.progress,
    required this.label,
    required this.lit,
  });

  static const _baseline = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final countStyle = theme.textTheme.headlineMedium!.copyWith(
      color: lit ? _palette.accentColor : Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w900,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final labelStyle = theme.textTheme.labelLarge!.copyWith(
      color: Colors.white.withValues(alpha: lit ? 0.95 : 0.6),
      fontSize: 13,
      fontWeight: FontWeight.w700,
    );
    final radius = const BorderRadius.vertical(top: Radius.circular(12), bottom: Radius.circular(4));
    final decoration = lit
        ? BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_palette.accent.first, _palette.accent.last.withValues(alpha: 0.75)],
            ),
            boxShadow: [BoxShadow(color: _palette.accentColor.withValues(alpha: 0.35), blurRadius: 28)],
          )
        : BoxDecoration(
            borderRadius: radius,
            color: Colors.white.withValues(alpha: 0.13),
            border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.5)),
          );

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Room for the count (and its gap) above the tallest bar.
              final countHeight = MediaQuery.textScalerOf(context).scale(countStyle.fontSize!) * countStyle.height!;
              final room = max(0.0, constraints.maxHeight - countHeight - 12);
              final height = max(_baseline, room * share * progress);
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatNumber((count * progress).roundToDouble()), maxLines: 1, style: countStyle),
                  ),
                  const SizedBox(height: 10),
                  FractionallySizedBox(
                    widthFactor: 0.78,
                    child: Container(height: height, decoration: decoration),
                  ),
                ],
              );
            },
          ),
        ),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
        const SizedBox(height: 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1, style: labelStyle),
        ),
      ],
    );
  }
}
