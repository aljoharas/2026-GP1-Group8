// Card 4: top games on a podium. Gold, silver and bronze steps rise, then the
// covers fly up onto them one at a time (#3, #2, #1), #1 glows as it lands,
// and the ranked list follows in the text zone. The covers float gently.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _stepsMs = 600;
const _firstFlightMs = 450;
const _flightGapMs = 250;
const _flightMs = 700;
const _glowMs = 900;
const _rowGapMs = 100;
const _floatAmplitude = 3.0; // ±3 px, about 6 px of travel
const _palette = WrappedPalette.topGames;

/// Gold, silver, bronze: [light, dark] for each rank.
const _medals = [
  [Color(0xFFFDE68A), Color(0xFFF59E0B)],
  [Color(0xFFF1F5F9), Color(0xFF94A3B8)],
  [Color(0xFFFED7AA), Color(0xFFC2410C)],
];

/// Podium step heights as a fraction of the visual zone's height, by rank.
const _stepHeights = [0.3, 0.22, 0.15];

class TopGamesCard extends StatefulWidget implements WrappedCard {
  /// 2 or 3 games, ranked.
  final List<WrappedGame> games;

  const TopGamesCard({super.key, required this.games});

  List<WrappedGame> get _podium => games.take(3).toList();

  @override
  List<String> get imageUrls => [for (final game in _podium) ?_coverOf(game)];

  @override
  State<TopGamesCard> createState() => _TopGamesCardState();
}

String? _coverOf(WrappedGame game) => game.coverImage ?? game.backgroundImage;

class _TopGamesCardState extends WrappedCardState<TopGamesCard> {
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  late final _motion = Listenable.merge([entrance, _float]);

  int get _count => widget._podium.length;

  // The lowest rank flies first, so #1 lands last.
  int _flightStartMs(int rank) => _firstFlightMs + (_count - 1 - rank) * _flightGapMs;

  int get _landedMs => _flightStartMs(0) + _flightMs;

  @override
  Duration get entranceDuration => Duration(milliseconds: _landedMs + _glowMs);

  late final _steps = msInterval(0, _stepsMs, entranceDuration, curve: Curves.easeOutCubic);
  late final _flights = [
    for (var rank = 0; rank < _count; rank++) msInterval(_flightStartMs(rank), _flightMs, entranceDuration),
  ];
  late final _glow = msInterval(_landedMs, _glowMs, entranceDuration);
  late final _eyebrowIn = msInterval(300, 450, entranceDuration, curve: Curves.easeOutCubic);
  late final _headlineIn = msInterval(420, 500, entranceDuration, curve: Curves.easeOutCubic);
  // The ranked list follows once #1 has landed.
  late final _rows = [
    for (var rank = 0; rank < _count; rank++)
      msInterval(_landedMs - 150 + rank * _rowGapMs, 450, entranceDuration, curve: Curves.easeOutCubic),
  ];

  @override
  List<AnimationController> get loops => [_float];

  @override
  Widget build(BuildContext context) {
    final games = widget._podium;
    final three = games.length == 3;
    // Left to right: #2 #1 #3, or #1 #2 with two games.
    final order = three ? const [1, 0, 2] : const [0, 1];

    final visual = Semantics(
      label: [
        for (final (i, game) in games.indexed) 'Number ${i + 1}, ${game.name}, ${formatHours(game.hours)}',
      ].join('. '),
      child: ExcludeSemantics(
        child: Stack(
          children: [
            Positioned.fill(child: WrappedHeroGlow(color: _palette.accentColor, strength: 0.14)),
            // Clipped, so covers rise into view from the zone's bottom edge.
            Positioned.fill(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth - 48;
                    final height = constraints.maxHeight;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomCenter,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final rank in order)
                                _slot(
                                  rank: rank,
                                  game: games[rank],
                                  columnWidth: width * (three ? (rank == 0 ? 0.36 : 0.32) : 0.42),
                                  stepHeight: height * _stepHeights[rank],
                                  travel: height,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
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
              WrappedEyebrow.zone(
                kTopGamesEyebrow,
                color: _palette.accentColor,
                icon: Icons.format_list_numbered_rounded,
              ),
            ),
            const SizedBox(height: 10),
            riseIn(_headlineIn.transform(t), WrappedHeadline(topGamesHeadline(games.length))),
            const SizedBox(height: 14),
            for (final (rank, game) in games.indexed)
              riseIn(_rows[rank].transform(t), _RankRow(rank: rank, game: game), distance: 12),
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

  Widget _slot({
    required int rank,
    required WrappedGame game,
    required double columnWidth,
    required double stepHeight,
    required double travel,
  }) {
    return SizedBox(
      width: columnWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _motion,
            builder: (context, child) {
              final t = entrance.value;
              final progress = _flights[rank].transform(t);
              final landing = Curves.easeOutBack.transform(progress);
              // Fades in with the flight, so the float never jumps on landing.
              final float = sin(2 * pi * (_float.value + rank / 3)) * _floatAmplitude * progress;
              return Transform.translate(
                offset: Offset(0, (1 - landing) * travel + float),
                child: _PodiumCover(
                  rank: rank,
                  game: game,
                  coverWidth: columnWidth * (rank == 0 ? 0.86 : 0.8),
                  glow: rank == 0 ? sin(pi * _glow.transform(t)) : 0,
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: entrance,
            builder: (context, child) {
              final t = _steps.transform(entrance.value);
              return Transform.translate(offset: Offset(0, (1 - t) * stepHeight), child: child);
            },
            child: _PodiumStep(rank: rank, height: stepHeight),
          ),
        ],
      ),
    );
  }
}

class _PodiumCover extends StatelessWidget {
  final int rank;
  final WrappedGame game;
  final double coverWidth;
  final double glow; // 0..1

  const _PodiumCover({required this.rank, required this.game, required this.coverWidth, required this.glow});

  static final _radius = BorderRadius.circular(16);

  @override
  Widget build(BuildContext context) {
    final first = rank == 0;
    final medal = _medals[rank];

    return SizedBox(
      width: coverWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _radius,
          boxShadow: [
            const BoxShadow(color: Color(0x80000000), blurRadius: 28, offset: Offset(0, 10)),
            // A steady medal glow, brighter on #1 as it lands.
            BoxShadow(
              color: medal.last.withValues(alpha: (first ? 0.35 : 0.18) + 0.45 * glow),
              blurRadius: 30 + 30 * glow,
              spreadRadius: 2 * glow,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _radius,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: _radius,
              border: Border.all(
                color: medal.first.withValues(alpha: first ? 0.9 : 0.55),
                width: first ? 2 : 1.4,
              ),
            ),
            child: AspectRatio(aspectRatio: 3 / 4, child: WrappedImage(_coverOf(game))),
          ),
        ),
      ),
    );
  }
}

/// One line of the ranked list: rank, name, hours.
class _RankRow extends StatelessWidget {
  final int rank;
  final WrappedGame game;

  const _RankRow({required this.rank, required this.game});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tabular = [FontFeature.tabularFigures()];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '${rank + 1}',
              style: theme.textTheme.headlineMedium!.copyWith(
                color: _palette.accentColor,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                height: 1.1,
                fontFeatures: tabular,
              ),
            ),
          ),
          Expanded(
            child: Text(
              game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium!.copyWith(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatHours(game.hours),
            style: theme.textTheme.bodyMedium!.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// A podium block in its medal colour, with the rank numeral cut into it.
class _PodiumStep extends StatelessWidget {
  final int rank;
  final double height;

  const _PodiumStep({required this.rank, required this.height});

  @override
  Widget build(BuildContext context) {
    final medal = _medals[rank];
    final first = rank == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              // Lit top edge.
              Container(height: 2.5, color: medal.first),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [medal.last.withValues(alpha: 0.55), medal.last.withValues(alpha: 0.08)],
                    ),
                  ),
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  // Shrinks on short steps (small screens) rather than clip.
                  child: FittedBox(fit: BoxFit.scaleDown, child: _numeral(context, medal, first)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numeral(BuildContext context, List<Color> medal, bool first) {
    return WrappedGradientText(
      '#${rank + 1}',
      colors: medal,
      style: Theme.of(context).textTheme.displaySmall!.copyWith(
        color: Colors.white,
        fontSize: first ? 40 : 30,
        fontWeight: FontWeight.w900,
        letterSpacing: -1,
        height: 1,
      ),
    );
  }
}
