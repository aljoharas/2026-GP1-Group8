// Card 6: trophies. The platinum trophy rises in, a light sweep crosses it
// once, then it floats; the count ticks up and the year's trophies stagger
// in below as a scrolling list.

import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _palette = WrappedPalette.trophies;
const _trophyAsset = 'assets/wrapped/platinum_trophy.png';
const _staggeredRows = 8;
const _rowGapMs = 60;
const _rowsStartMs = 750;

class TrophiesCard extends StatefulWidget implements WrappedCard {
  final int count;

  /// Newest first.
  final List<WrappedTrophy> trophies;

  const TrophiesCard({super.key, required this.count, this.trophies = const []});

  @override
  List<String> get imageUrls => [for (final trophy in trophies.take(_staggeredRows)) ?trophy.iconUrl];

  @override
  State<TrophiesCard> createState() => _TrophiesCardState();
}

class _TrophiesCardState extends WrappedCardState<TrophiesCard> {
  static const _total = Duration(milliseconds: _rowsStartMs + _staggeredRows * _rowGapMs + 450);
  static final _heroIn = msInterval(0, 700, _total, curve: Curves.easeOutBack);
  static final _heroFade = msInterval(0, 300, _total);
  static final _sweep = msInterval(650, 900, _total, curve: Curves.easeInOut);
  static final _eyebrowIn = msInterval(300, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(420, 500, _total, curve: Curves.easeOutCubic);
  static final _count = msInterval(420, 1000, _total, curve: Curves.easeOutCubic);
  static final _rows = [
    for (var i = 0; i < _staggeredRows; i++)
      msInterval(_rowsStartMs + i * _rowGapMs, 450, _total, curve: Curves.easeOutCubic),
  ];

  late final _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  late final _heroMotion = Listenable.merge([entrance, _float]);

  @override
  Duration get entranceDuration => _total;

  @override
  List<AnimationController> get loops => [_float];

  @override
  Widget build(BuildContext context) {
    final hasList = widget.trophies.isNotEmpty;

    final hero = Semantics(
      label: trophiesSemantics(widget.count),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = min(constraints.maxHeight * 0.86, constraints.maxWidth * 0.6);
            return Stack(
              alignment: Alignment.center,
              children: [
                const Positioned.fill(child: WrappedHeroGlow(color: Color(0xFF7DD3FC), strength: 0.22)),
                AnimatedBuilder(
                  animation: _heroMotion,
                  builder: (context, child) {
                    final t = _heroIn.transform(entrance.value);
                    final float = sin(2 * pi * _float.value) * 3 * entrance.value;
                    return Opacity(
                      opacity: _heroFade.transform(entrance.value),
                      child: Transform.translate(
                        offset: Offset(0, 40 * (1 - t) + float),
                        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
                      ),
                    );
                  },
                  child: AnimatedBuilder(
                    animation: entrance,
                    builder: (context, child) => _LightSweep(progress: _sweep.transform(entrance.value), child: child!),
                    child: SizedBox.square(dimension: side, child: const _Trophy()),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    final text = AnimatedBuilder(
      animation: entrance,
      builder: (context, _) {
        final t = entrance.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: hasList ? MainAxisSize.max : MainAxisSize.min,
          children: [
            riseIn(
              _eyebrowIn.transform(t),
              WrappedEyebrow.zone(kTrophiesEyebrow, color: _palette.accentColor, icon: Icons.emoji_events_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(
              _headlineIn.transform(t),
              WrappedHeadline(trophiesHeadline((widget.count * _count.transform(t)).round())),
            ),
            if (hasList) ...[
              const SizedBox(height: 8),
              Expanded(
                child: _TrophyList(trophies: widget.trophies, entrance: entrance, rows: _rows),
              ),
            ],
          ],
        );
      },
    );

    return WrappedBackdrop(
      palette: _palette,
      drift: ambient,
      child: WrappedSplitLayout(visual: hero, text: text, expandText: hasList, visualFraction: hasList ? 0.43 : 0.6),
    );
  }
}

/// The platinum trophy art, or a large trophy icon when the asset is missing.
class _Trophy extends StatelessWidget {
  const _Trophy();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _trophyAsset,
      fit: BoxFit.contain,
      errorBuilder: (context, _, _) => LayoutBuilder(
        builder: (context, constraints) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF1F7FB), Color(0xFFB9D7EA), Color(0xFF6E97B8)],
          ).createShader(bounds),
          child: Icon(Icons.emoji_events_rounded, size: constraints.biggest.shortestSide),
        ),
      ),
    );
  }
}

/// A diagonal band of light across [child], left to right as [progress]
/// goes 0 → 1. Only the child's opaque pixels light up.
class _LightSweep extends StatelessWidget {
  final double progress;
  final Widget child;

  const _LightSweep({required this.progress, required this.child});

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return child;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)],
        stops: const [0.42, 0.5, 0.58],
        transform: _Slide(-1.2 + 2.4 * progress),
      ).createShader(bounds),
      child: child,
    );
  }
}

class _Slide extends GradientTransform {
  final double fraction;

  const _Slide(this.fraction);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fraction, bounds.height * fraction, 0);
}

/// The trophies, fading out at the top and bottom edges to show they scroll.
/// Vertical drags scroll the list; horizontal ones still reach the PageView.
class _TrophyList extends StatelessWidget {
  final List<WrappedTrophy> trophies;
  final Animation<double> entrance;
  final List<Curve> rows;

  const _TrophyList({required this.trophies, required this.entrance, required this.rows});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0.0, 0.07, 0.86, 1.0],
      ).createShader(bounds),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 28),
        itemCount: trophies.length,
        itemBuilder: (context, i) {
          final row = _TrophyRow(trophies[i]);
          if (i >= rows.length) return row;
          return AnimatedBuilder(
            animation: entrance,
            builder: (context, child) => riseIn(rows[i].transform(entrance.value), child!, distance: 14),
            child: row,
          );
        },
      ),
    );
  }
}

class _TrophyRow extends StatelessWidget {
  final WrappedTrophy trophy;

  const _TrophyRow(this.trophy);

  static final _radius = BorderRadius.circular(10);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08)),
      child: Icon(Icons.emoji_events_rounded, size: 22, color: _palette.accentColor),
    );
    final icon = trophy.iconUrl;
    final subtitle = trophySubtitle(trophy);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: _radius,
            child: SizedBox.square(
              dimension: 44,
              child: icon == null
                  ? placeholder
                  : CachedNetworkImage(
                      imageUrl: icon,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => placeholder,
                      errorWidget: (_, _, _) => placeholder,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trophy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall!.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
