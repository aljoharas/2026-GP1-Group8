// Card 0: the intro. Two tilted strips of game covers scroll past in
// opposite directions above and below the "2026 Endgame" title.
//
// The covers are the user's own games for the year; when there are fewer
// than [_targetCovers], popular games from the catalogue fill the rest so
// the strips always look full.

import 'package:flutter/material.dart';

import '../../../services/home_service.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _targetCovers = 12;

/// Covers per strip; repeated if there are fewer, so a strip is always wider
/// than the screen.
const _minTilesPerRow = 6;

/// How long one strip takes to scroll through its covers once.
const _loopDuration = Duration(seconds: 30);

/// Strip tilt in radians (rising to the right).
const _tilt = -0.09;

const _base = Color(0xFF0B0920);
const _glow = Color(0xFF3B1A78);
const _eyebrowColor = Color(0xFF34D3B0);
const _titleGradient = [Color(0xFF34D399), Color(0xFF22D3EE)];
const _subtitleColor = Color(0xFFB8B5D6);

class IntroCard extends StatefulWidget implements WrappedCard {
  final int year;
  final List<String> covers;

  const IntroCard({super.key, required this.year, this.covers = const []});

  @override
  List<String> get imageUrls => covers.take(_targetCovers).toList();

  @override
  State<IntroCard> createState() => _IntroCardState();
}

class _IntroCardState extends WrappedCardState<IntroCard> {
  static const _total = Duration(milliseconds: 1400);
  static final _rowsIn = msInterval(0, 600, _total, curve: Curves.easeOut);
  static final _eyebrowIn = msInterval(250, 500, _total, curve: Curves.easeOutCubic);
  static final _yearIn = msInterval(400, 550, _total, curve: Curves.easeOutCubic);
  static final _titleIn = msInterval(550, 550, _total, curve: Curves.easeOutCubic);
  static final _lineIn = msInterval(750, 550, _total, curve: Curves.easeOutCubic);

  late final _scroll = AnimationController(vsync: this, duration: _loopDuration);

  /// Popular games added after the user's own covers, when they have few.
  List<String> _fillers = const [];

  @override
  Duration get entranceDuration => _total;

  @override
  List<AnimationController> get loops => [_scroll];

  @override
  void initState() {
    super.initState();
    if (widget.covers.length < _targetCovers) _loadFillers();
  }

  Future<void> _loadFillers() async {
    final result = await HomeService().getPopular();
    if (!mounted || result['success'] != true) return;
    final own = widget.covers.toSet();
    final fillers = <String>[
      for (final game in (result['games'] as List? ?? const []))
        if (game case {'cover_image': final Object? cover, 'background_image': final Object? background})
          if (cover ?? background case final String url when url.isNotEmpty && !own.contains(url)) url,
    ];
    setState(() => _fillers = fillers);
  }

  /// The user's covers first, then popular ones, up to [_targetCovers].
  List<String> get _allCovers => [...widget.covers, ..._fillers].take(_targetCovers).toList();

  @override
  Widget build(BuildContext context) {
    final covers = _allCovers;
    // Alternate covers between the strips so neither gets only fillers.
    final top = [for (var i = 0; i < covers.length; i += 2) covers[i]];
    final bottom = [for (var i = 1; i < covers.length; i += 2) covers[i]];

    return ColoredBox(
      color: _base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, 0.05),
                radius: 0.75,
                colors: [_glow, Color(0x00000000)],
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final tileWidth = size.width * 0.26;
              final tile = Size(tileWidth, tileWidth * 1.3);
              Widget strip(List<String> urls, {required bool reverse, required double centreY}) => Positioned(
                left: -size.width * 0.15,
                right: -size.width * 0.15,
                top: centreY - tile.height / 2 - 20,
                height: tile.height + 40,
                child: AnimatedBuilder(
                  animation: entrance,
                  builder: (context, child) => Opacity(opacity: _rowsIn.transform(entrance.value), child: child),
                  child: Transform.rotate(
                    angle: _tilt,
                    child: _CoverStrip(urls: urls, tile: tile, motion: _scroll, reverse: reverse),
                  ),
                ),
              );
              return Stack(
                children: [
                  strip(top, reverse: false, centreY: size.height * 0.22),
                  strip(bottom, reverse: true, centreY: size.height * 0.85),
                ],
              );
            },
          ),
          Align(alignment: const Alignment(0, 0.08), child: _title(context)),
        ],
      ),
    );
  }

  Widget _title(BuildContext context) {
    final big = WrappedText.display(context).copyWith(
      fontSize: 64,
      height: 1.05,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
    );
    return Semantics(
      label: 'Your year in games. ${widget.year} Endgame. $kIntroLine',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: entrance,
          builder: (context, _) {
            final t = entrance.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  riseIn(
                    _eyebrowIn.transform(t),
                    WrappedEyebrow(kIntroEyebrow, color: _eyebrowColor, fontSize: 13, letterSpacing: 2.4),
                  ),
                  const SizedBox(height: 14),
                  riseIn(
                    _yearIn.transform(t),
                    FittedBox(fit: BoxFit.scaleDown, child: Text('${widget.year}', style: big)),
                  ),
                  riseIn(
                    _titleIn.transform(t),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: WrappedGradientText('Endgame', style: big, colors: _titleGradient),
                    ),
                  ),
                  const SizedBox(height: 14),
                  riseIn(
                    _lineIn.transform(t),
                    Text(
                      kIntroLine,
                      textAlign: TextAlign.center,
                      style: WrappedText.medium(context).copyWith(color: _subtitleColor, fontSize: 17, fontWeight: FontWeight.w400),
                    ),
                    distance: 12,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One endless strip of covers. [motion] runs 0 → 1 once per pass; each pass
/// moves the strip by exactly its own length, so the loop has no visible jump.
class _CoverStrip extends StatelessWidget {
  final List<String> urls;
  final Size tile;
  final Animation<double> motion;
  final bool reverse;

  const _CoverStrip({required this.urls, required this.tile, required this.motion, required this.reverse});

  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    // Repeat the whole list (a b c a b c), never a partial one, so the strip
    // never puts the same cover next to itself where it loops around.
    final repeats = urls.isEmpty ? 0 : (_minTilesPerRow / urls.length).ceil();
    final List<String?> tiles = urls.isEmpty
        ? List.filled(_minTilesPerRow, null)
        : [for (var r = 0; r < repeats; r++) ...urls];
    return ClipRect(
      child: Flow(
        delegate: _StripDelegate(motion: motion, tile: tile, gap: _gap, reverse: reverse),
        children: [for (final url in tiles) _CoverTile(url)],
      ),
    );
  }
}

class _StripDelegate extends FlowDelegate {
  final Animation<double> motion;
  final Size tile;
  final double gap;
  final bool reverse;

  _StripDelegate({required this.motion, required this.tile, required this.gap, required this.reverse})
    : super(repaint: motion);

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) => BoxConstraints.tight(tile);

  @override
  void paintChildren(FlowPaintingContext context) {
    final n = context.childCount;
    final step = tile.width + gap;
    final length = n * step;
    final shift = (reverse ? -motion.value : motion.value) * length;
    final y = (context.size.height - tile.height) / 2;
    for (var i = 0; i < n; i++) {
      // Wrap each tile around so it re-enters on the other side.
      final x = (i * step - shift) % length - step;
      if (x > context.size.width) continue;
      context.paintChild(i, transform: Matrix4.translationValues(x, y, 0));
    }
  }

  @override
  bool shouldRepaint(_StripDelegate old) =>
      old.motion != motion || old.tile != tile || old.gap != gap || old.reverse != reverse;

  @override
  bool shouldRelayout(_StripDelegate old) => old.tile != tile;
}

class _CoverTile extends StatelessWidget {
  final String? url;

  const _CoverTile(this.url);

  static final _radius = BorderRadius.circular(16);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: ClipRRect(borderRadius: _radius, child: WrappedImage(url)),
    );
  }
}
