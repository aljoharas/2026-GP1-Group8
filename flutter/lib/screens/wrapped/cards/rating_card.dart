// Card 9: ratings. The average counts up in stars while five stars fill
// beside it, then the 5★ → 1★ breakdown bars grow in one by one.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _palette = WrappedPalette.rating;
const _starsMs = 1100;
const _rowGapMs = 80;
const _rowMs = 500;

class RatingCard extends StatefulWidget implements WrappedCard {
  final WrappedRating rating;

  const RatingCard({super.key, required this.rating});

  @override
  List<String> get imageUrls => const [];

  @override
  State<RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends WrappedCardState<RatingCard> {
  static const _total = Duration(milliseconds: _starsMs + 4 * _rowGapMs + _rowMs);
  static final _visualIn = msInterval(0, 400, _total, curve: Curves.easeOutCubic);
  static final _count = msInterval(0, _starsMs, _total, curve: Curves.easeOutCubic);
  static final _eyebrowIn = msInterval(300, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(420, 500, _total, curve: Curves.easeOutCubic);
  static final _lineIn = msInterval(560, 500, _total, curve: Curves.easeOutCubic);
  // Top row (5★) first.
  static final _rows = [
    for (var i = 0; i < 5; i++) msInterval(_starsMs + i * _rowGapMs, _rowMs, _total, curve: Curves.easeOutCubic),
  ];

  @override
  Duration get entranceDuration => _total;

  @override
  Widget build(BuildContext context) {
    final rating = widget.rating;
    final line = ratingLine(rating);

    final visual = Semantics(
      label: ratingSemantics(rating),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: constraints.maxWidth,
                child: AnimatedBuilder(
                  animation: entrance,
                  builder: (context, _) => _RatingVisual(
                    rating: rating,
                    // Rounded to what the number shows, so stars and number agree.
                    stars: (rating.averageStars * _count.transform(entrance.value) * 10).round() / 10,
                    opacity: _visualIn.transform(entrance.value),
                    rows: [for (final row in _rows) row.transform(entrance.value)],
                  ),
                ),
              ),
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
              WrappedEyebrow.zone(ratingEyebrow(rating), color: _palette.accentColor, icon: Icons.star_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(_headlineIn.transform(t), WrappedHeadline(ratingHeadline(rating))),
            if (line != null) ...[
              const SizedBox(height: 12),
              riseIn(_lineIn.transform(t), WrappedSupportingLine(line), distance: 12),
            ],
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
            Positioned.fill(child: WrappedHeroGlow(color: _palette.accent.last, strength: 0.18)),
            Positioned.fill(child: Center(child: visual)),
          ],
        ),
        text: text,
      ),
    );
  }
}

class _RatingVisual extends StatelessWidget {
  final WrappedRating rating;

  /// The average shown so far, in stars.
  final double stars;
  final double opacity;

  /// Each breakdown row's growth, 5★ first.
  final List<double> rows;

  const _RatingVisual({required this.rating, required this.stars, required this.opacity, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = rating.starCounts;
    final most = counts.reduce(max);
    final caption = theme.textTheme.bodyMedium!.copyWith(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 14,
      fontWeight: FontWeight.w500,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Opacity(
          opacity: opacity,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              WrappedGradientText(
                stars.toStringAsFixed(1),
                colors: _palette.accent,
                style: WrappedText.huge(context).copyWith(fontSize: 92, letterSpacing: -3),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: StarRow(stars: stars, size: 30),
                    ),
                    const SizedBox(height: 6),
                    Text(ratingAverageCaption(rating.ratedGames), maxLines: 2, style: caption),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Left out when the server sent no breakdown, rather than five zeros.
        if (rating.breakdown.isNotEmpty) const SizedBox(height: 18),
        if (rating.breakdown.isNotEmpty)
          for (var n = 5; n >= 1; n--)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: _BreakdownRow(
                stars: n,
                count: counts[n - 1],
                share: most == 0 ? 0 : counts[n - 1] / most,
                progress: rows[5 - n],
              ),
            ),
      ],
    );
  }
}

/// Five stars filled up to [stars], the last one partly.
class StarRow extends StatelessWidget {
  final double stars;
  final double size;

  const StarRow({super.key, required this.stars, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              Icon(Icons.star_rounded, size: size, color: Colors.white.withValues(alpha: 0.16)),
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: (stars - i).clamp(0.0, 1.0),
                  child: Icon(Icons.star_rounded, size: size, color: _palette.accentColor),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final int stars;
  final int count;
  final double share;
  final double progress;

  const _BreakdownRow({required this.stars, required this.count, required this.share, required this.progress});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!.copyWith(
      color: Colors.white.withValues(alpha: count == 0 ? 0.4 : 0.85),
      fontSize: 13,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Row(
            children: [
              Text('$stars', style: style),
              const SizedBox(width: 2),
              Icon(Icons.star_rounded, size: 13, color: style.color),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (count > 0 && progress > 0)
                FractionallySizedBox(
                  widthFactor: max(0.02, share * progress),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: LinearGradient(colors: [_palette.accent.last, _palette.accent.first]),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 32,
          child: Text('${(count * progress).round()}', textAlign: TextAlign.right, style: style),
        ),
      ],
    );
  }
}
