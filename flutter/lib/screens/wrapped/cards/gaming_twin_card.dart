// Card 11: your gaming twin. Your avatar pops onto a dot grid, a line draws
// itself up to your most similar friend, their avatar pops in where it
// lands, and the two bob gently, still connected.

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _palette = WrappedPalette.gamingTwin;
final _shadowDisc = Color.lerp(_palette.accentColor, Colors.black, 0.55)!;
const _maxNode = 88.0;
const _discOffset = 6.0;
const _bob = 3.0; // ±3 px

class GamingTwinCard extends StatefulWidget implements WrappedCard {
  final WrappedUser me;
  final WrappedSimilarFriend friend;

  const GamingTwinCard({super.key, required this.me, required this.friend});

  @override
  List<String> get imageUrls => [?me.avatarUrl, ?friend.user.avatarUrl];

  @override
  State<GamingTwinCard> createState() => _GamingTwinCardState();
}

class _GamingTwinCardState extends WrappedCardState<GamingTwinCard> {
  static const _total = Duration(milliseconds: 2300);
  static final _mePop = msInterval(0, 500, _total, curve: Curves.easeOutBack);
  static final _meFade = msInterval(0, 200, _total);
  static final _line = msInterval(450, 600, _total, curve: Curves.easeOutCubic);
  static final _friendPop = msInterval(1000, 500, _total, curve: Curves.easeOutBack);
  static final _friendFade = msInterval(1000, 200, _total);
  static final _eyebrowIn = msInterval(600, 450, _total, curve: Curves.easeOutCubic);
  static final _headlineIn = msInterval(1100, 500, _total, curve: Curves.easeOutCubic);
  static final _statsIn = msInterval(1250, 500, _total, curve: Curves.easeOutCubic);
  static final _match = msInterval(1250, 1000, _total, curve: Curves.easeOutCubic);

  late final _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  late final _motion = Listenable.merge([entrance, _float]);

  @override
  Duration get entranceDuration => _total;

  @override
  List<AnimationController> get loops => [_float];

  @override
  Widget build(BuildContext context) {
    final friend = widget.friend;
    final genres = friend.sharedGenres;

    final visual = Semantics(
      label: similarFriendSemantics(friend),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) =>
              AnimatedBuilder(animation: _motion, builder: (context, _) => _nodes(constraints.biggest)),
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
              WrappedEyebrow.zone(kGamingTwinEyebrow, color: _palette.accentColor, icon: Icons.people_alt_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(_headlineIn.transform(t), WrappedHeadline(displayName(friend.user).toUpperCase())),
            const SizedBox(height: 22),
            riseIn(
              _statsIn.transform(t),
              distance: 12,
              WrappedStatPairs(
                accent: _palette.accentColor,
                stats: [
                  WrappedStat(
                    icon: Icons.join_inner_rounded,
                    label: kMatchLabel,
                    value: '${(friend.matchPercent * _match.transform(t)).round()}%',
                  ),
                  if (genres.isNotEmpty)
                    WrappedStat(icon: Icons.favorite_rounded, label: kBothLoveLabel, value: sharedGenresValue(genres)),
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
      glowOpacity: 0.7,
      behind: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0.0, 0.45, 0.65],
        ).createShader(bounds),
        child: const RepaintBoundary(child: CustomPaint(painter: _DotGridPainter())),
      ),
      child: WrappedSplitLayout(visual: visual, text: text),
    );
  }

  Widget _nodes(Size size) {
    final t = entrance.value;
    final node = min(_maxNode, size.height * 0.34);
    final settled = _friendPop.transform(t).clamp(0.0, 1.0);
    final bob = 2 * pi * _float.value;
    // Each tag (under your node, above your friend's, so neither meets the
    // line) needs about this much room.
    const tagRoom = 36.0;

    final me =
        Offset(size.width * 0.27, size.height - node / 2 - tagRoom - _discOffset) +
        Offset(0, sin(bob) * _bob * settled);
    final friend = Offset(size.width * 0.73, tagRoom + node / 2 + _bob) + Offset(0, sin(bob + pi) * _bob * settled);

    final gap = node / 2 + 8;
    final direction = (friend - me) / (friend - me).distance;
    final start = me + direction * gap;
    final end = friend - direction * gap;

    Widget place(Offset centre, double pop, double fade, WrappedUser user, {required bool tagAbove}) {
      final tag = _Tag(user.username ?? displayName(user));
      final nodeTop = centre.dy - node / 2;
      return Positioned(
        left: centre.dx - 90,
        width: 180,
        // Pinned by the node's edge, so the node sits at centre either way.
        top: tagAbove ? null : nodeTop,
        bottom: tagAbove ? size.height - (nodeTop + node + _discOffset) : null,
        child: Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: max(0.0, pop),
            alignment: tagAbove ? Alignment.bottomCenter : Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tagAbove) ...[tag, const SizedBox(height: 10)],
                _Node(user: user, size: node),
                if (!tagAbove) ...[const SizedBox(height: 10), tag],
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: WrappedHeroGlow(color: _palette.accent.last, strength: 0.14)),
        Positioned.fill(
          child: CustomPaint(
            painter: _LinkPainter(start: start, end: end, progress: _line.transform(t)),
          ),
        ),
        place(me, _mePop.transform(t), _meFade.transform(t), widget.me, tagAbove: false),
        place(friend, _friendPop.transform(t), _friendFade.transform(t), widget.friend.user, tagAbove: true),
      ],
    );
  }
}

/// An avatar with an accent ring and a solid offset disc behind it.
class _Node extends StatelessWidget {
  final WrappedUser user;
  final double size;

  const _Node({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + _discOffset,
      height: size + _discOffset,
      child: Stack(
        children: [
          Positioned(
            left: _discOffset,
            top: _discOffset,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _shadowDisc),
            ),
          ),
          Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: _palette.accentColor),
            child: WrappedAvatar(url: user.avatarUrl, name: user.username, size: size - 4, tint: _palette.accentColor),
          ),
        ],
      ),
    );
  }
}

/// A username label on an accent block, in monospace.
class _Tag extends StatelessWidget {
  final String text;

  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _palette.accentColor, borderRadius: BorderRadius.circular(3)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.2),
        style: TextStyle(
          color: _palette.base,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier New', 'Courier'],
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

/// The line from [start] to [end], drawn up to [progress].
class _LinkPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final double progress;

  const _LinkPainter({required this.start, required this.end, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final tip = Offset.lerp(start, end, progress)!;
    final paint = Paint()
      ..color = _palette.accentColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, tip, Paint.from(paint)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawLine(start, tip, paint);
    canvas.drawCircle(start, 3.5, paint);
    canvas.drawCircle(tip, 3.5, paint);
  }

  @override
  bool shouldRepaint(_LinkPainter old) => old.start != start || old.end != end || old.progress != progress;
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  static const _spacing = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.09);
    for (var y = _spacing / 2; y < size.height; y += _spacing) {
      for (var x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}
