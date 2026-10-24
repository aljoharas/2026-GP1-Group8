// Card 7: player type. A full-bleed photo for the type drifts in a slow Ken
// Burns zoom; the type's name lands, and the reason fades in after it. With
// no photo, a large outlined icon glows on the card's gradient instead.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/wrapped.dart';
import '../wrapped_card.dart';
import '../wrapped_copy.dart';

const _palette = WrappedPalette.playerType;

String _photoAsset(PlayerType type) => 'assets/wrapped/types/${type.key}.png';

IconData _icon(PlayerType type) => switch (type) {
  PlayerType.creditsChaser => Icons.sports_score_outlined,
  PlayerType.foreverInProgress => Icons.all_inclusive_outlined,
  PlayerType.theCloser => Icons.task_alt_outlined,
  PlayerType.theJuggler => Icons.layers_outlined,
  PlayerType.saveAndQuit => Icons.save_outlined,
};

class PlayerTypeCard extends StatefulWidget implements WrappedCard {
  final PlayerType type;
  final WrappedPlayStyle style;

  const PlayerTypeCard({super.key, required this.type, required this.style});

  @override
  List<String> get imageUrls => const [];

  @override
  State<PlayerTypeCard> createState() => _PlayerTypeCardState();
}

class _PlayerTypeCardState extends WrappedCardState<PlayerTypeCard> {
  static const _nameMs = 450;
  static const _total = Duration(milliseconds: _nameMs + 400 + 600);
  static final _visualIn = msInterval(0, 600, _total, curve: Curves.easeOutCubic);
  static final _eyebrowIn = msInterval(250, 450, _total, curve: Curves.easeOutCubic);
  static final _nameIn = msInterval(_nameMs, 550, _total, curve: Curves.easeOutCubic);
  static final _reasonIn = msInterval(_nameMs + 400, 600, _total, curve: Curves.easeOut);

  late final _kenBurns = AnimationController(vsync: this, duration: WrappedKenBurns.period);

  /// Null until the asset lookup finishes.
  bool? _hasPhoto;

  @override
  Duration get entranceDuration => _total;

  @override
  List<AnimationController> get loops => [_kenBurns];

  @override
  void initState() {
    super.initState();
    _checkPhoto();
  }

  @override
  void didUpdateWidget(PlayerTypeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) _checkPhoto();
  }

  Future<void> _checkPhoto() async {
    final type = widget.type;
    bool found;
    try {
      await rootBundle.load(_photoAsset(type));
      found = true;
    } catch (_) {
      found = false;
    }
    if (mounted && widget.type == type) setState(() => _hasPhoto = found);
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final hasPhoto = _hasPhoto ?? false;

    final photo = AnimatedBuilder(
      animation: entrance,
      builder: (context, child) => Opacity(opacity: _visualIn.transform(entrance.value), child: child),
      child: Stack(
        fit: StackFit.expand,
        children: [
          WrappedKenBurns(
            controller: _kenBurns,
            child: Image.asset(_photoAsset(type), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
          ),
          // A strong scrim under the text zone, a light one under the chrome.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x73000000),
                  const Color(0x00000000),
                  _palette.base.withValues(alpha: 0.75),
                  _palette.base.withValues(alpha: 0.97),
                ],
                stops: const [0.0, 0.28, 0.55, 0.78],
              ),
            ),
          ),
        ],
      ),
    );

    final icon = LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxHeight * 0.62, constraints.maxWidth * 0.5);
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(child: WrappedHeroGlow(color: _palette.accentColor, strength: 0.26)),
            AnimatedBuilder(
              animation: entrance,
              builder: (context, child) {
                final t = _visualIn.transform(entrance.value);
                return Opacity(
                  opacity: t,
                  child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
                );
              },
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _palette.accent,
                ).createShader(bounds),
                child: Icon(_icon(type), size: side),
              ),
            ),
          ],
        );
      },
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
              WrappedEyebrow.zone(kPlayerTypeEyebrow, color: _palette.accentColor, icon: Icons.person_rounded),
            ),
            const SizedBox(height: 10),
            riseIn(_nameIn.transform(t), WrappedHeadline(playerTypeName(type), maxLines: 2)),
            const SizedBox(height: 14),
            Opacity(
              opacity: _reasonIn.transform(t),
              child: WrappedSupportingLine(playerTypeReason(type)),
            ),
          ],
        );
      },
    );

    return WrappedBackdrop(
      palette: _palette,
      drift: ambient,
      glowOpacity: hasPhoto ? 0.35 : 1,
      behind: hasPhoto ? photo : null,
      child: WrappedSplitLayout(
        visual: Semantics(
          label: '${playerTypeName(type)}. ${playerTypeReason(type)}',
          child: ExcludeSemantics(child: _hasPhoto == false ? icon : const SizedBox.expand()),
        ),
        text: text,
      ),
    );
  }
}
