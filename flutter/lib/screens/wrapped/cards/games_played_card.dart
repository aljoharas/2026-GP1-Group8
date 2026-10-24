// Card 2: games played. The year's covers spin on a tilted 3D carousel and
// slow to a drift, while the count pops up in the headline.

import 'dart:math';

import 'package:flutter/material.dart';

import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _maxCovers = 12;
const _minTiles = 8;
const _spinMs = 2000;
const _spinTurns = 1.25;
const _tilt = 0.32;
const _radiusInTiles = 2.1;
const _palette = WrappedPalette.gamesPlayed;

class GamesPlayedCard extends StatefulWidget implements WrappedCard {
  final int count;
  final List<String> covers;

  const GamesPlayedCard({super.key, required this.count, this.covers = const []});

  @override
  List<String> get imageUrls => covers.take(_maxCovers).toList();

  @override
  State<GamesPlayedCard> createState() => _GamesPlayedCardState();
}

/// Up to [_maxCovers] covers, repeated to at least [_minTiles]; with none,
/// placeholder tiles (null).
List<String?> _ringTiles(List<String> covers) {
  if (covers.isEmpty) return List.filled(_minTiles, null);
  final picked = covers.take(_maxCovers).toList();
  return [for (var i = 0; i < max(picked.length, _minTiles); i++) picked[i % picked.length]];
}

class _GamesPlayedCardState extends WrappedCardState<GamesPlayedCard> {
  static const _total = Duration(milliseconds: _spinMs + 100);
  static final _spin = msInterval(0, _spinMs, _total, curve: Curves.easeOutCubic);
  static final _ringIn = msInterval(0, 400, _total, curve: Curves.easeOut);
  static final _eyebrowIn = msInterval(300, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(420, 500, _total, curve: Curves.easeOutCubic);
  static final _count = msInterval(420, 900, _total, curve: Curves.easeOutCubic);
  static final _pop = msInterval(420, 1100, _total, curve: Curves.elasticOut);
  static final _lineIn = msInterval(560, 500, _total, curve: Curves.easeOutCubic);

  // One slow full turn, so the loop wraps without a jump.
  late final _drift = AnimationController(vsync: this, duration: const Duration(seconds: 120));
  late final _ringMotion = Listenable.merge([entrance, _drift]);

  @override
  Duration get entranceDuration => _total;

  @override
  List<AnimationController> get loops => [_drift];

  double _ringAngle() => 2 * pi * (_spinTurns * _spin.transform(entrance.value) + _drift.value);

  @override
  Widget build(BuildContext context) {
    final count = widget.count;
    final headline = WrappedText.display(context);

    final visual = Semantics(
      label: 'You played $count ${count == 1 ? 'game' : 'games'} this year',
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Positioned.fill(child: WrappedHeroGlow(color: _palette.accentColor, strength: 0.16)),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // With radius = 2.1 tile widths, the ring spans about 5.4
                  // tiles across (side tiles stick out past the radius) and
                  // 2.5 down (back tiles are smaller), so size the tiles to
                  // fit both ways inside the card's 24 px margins.
                  final tileWidth = min((constraints.maxWidth - 48) / 5.4, constraints.maxHeight / 2.5);
                  final tile = Size(tileWidth, tileWidth * 4 / 3);
                  final radius = tileWidth * _radiusInTiles;
                  return AnimatedBuilder(
                    animation: entrance,
                    builder: (context, child) => Opacity(opacity: _ringIn.transform(entrance.value), child: child),
                    child: Flow(
                      delegate: _CarouselDelegate(
                        motion: _ringMotion,
                        angle: _ringAngle,
                        radius: radius,
                        tilt: _tilt,
                        tile: tile,
                      ),
                      children: [for (final url in _ringTiles(widget.covers)) _CoverTile(url)],
                    ),
                  );
                },
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
              WrappedEyebrow.zone(kGamesPlayedEyebrow, color: _palette.accentColor, icon: Icons.sports_esports_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(
              _headlineIn.transform(t),
              // The number pops on its own; the word stays put.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.6 + 0.4 * _pop.transform(t),
                      alignment: Alignment.bottomCenter,
                      child: Text(
                        formatNumber((count * _count.transform(t)).roundToDouble()),
                        style: headline.copyWith(color: _palette.accentColor),
                      ),
                    ),
                    Text(' ${gamesPlayedUnit(count)}', style: headline),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            riseIn(_lineIn.transform(t), WrappedSupportingLine(gamesPlayedLine(count)), distance: 12),
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

/// Places the tiles on a ring seen from slightly above, rotated by [angle]:
/// tiles at the back are smaller, dimmer and painted first. Tiles stay
/// upright. Repaints only; no rebuild per frame.
class _CarouselDelegate extends FlowDelegate {
  final Listenable motion;
  final double Function() angle;
  final double radius;

  /// How flat the ring looks: 0 is edge-on, 1 is seen from straight above.
  final double tilt;
  final Size tile;

  _CarouselDelegate({
    required this.motion,
    required this.angle,
    required this.radius,
    required this.tilt,
    required this.tile,
  }) : super(repaint: motion);

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) => BoxConstraints.tight(tile);

  @override
  void paintChildren(FlowPaintingContext context) {
    final centre = context.size.center(Offset.zero);
    final base = angle();
    final n = context.childCount;

    // depth: -1 at the back of the ring, 1 at the front.
    final placed = [
      for (var i = 0; i < n; i++) (index: i, theta: base + 2 * pi * i / n, depth: sin(base + 2 * pi * i / n)),
    ]..sort((a, b) => a.depth.compareTo(b.depth));

    for (final p in placed) {
      final front = (p.depth + 1) / 2;
      final scale = 0.62 + 0.38 * front;
      final at = centre + Offset(cos(p.theta) * radius, p.depth * radius * tilt);
      final transform = Matrix4.translationValues(at.dx, at.dy, 0)
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-tile.width / 2, -tile.height / 2, 0, 1);
      context.paintChild(p.index, transform: transform, opacity: 0.35 + 0.65 * front);
    }
  }

  @override
  bool shouldRepaint(_CarouselDelegate old) =>
      old.motion != motion || old.radius != radius || old.tilt != tilt || old.tile != tile;

  @override
  bool shouldRelayout(_CarouselDelegate old) => old.tile != tile;
}

class _CoverTile extends StatelessWidget {
  final String? url;

  const _CoverTile(this.url);

  static final _radius = BorderRadius.circular(14);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 22, offset: Offset(0, 10))],
      ),
      position: DecorationPosition.background,
      child: ClipRRect(
        borderRadius: _radius,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: _radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.2),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x40000000)],
              stops: [0.0, 0.4, 1.0],
            ),
          ),
          child: WrappedImage(url),
        ),
      ),
    );
  }
}
