import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/achievement_guide.dart';
import '../../providers/game_provider.dart';
import '../../providers/logged_games_provider.dart';
import '../../services/platinum_seen_store.dart';
import '../../widgets/platinum_celebration.dart';

const _bg = Color(0xFF0E0E12);
const _surface = Color(0xFF16161E);
const _surface2 = Color(0xFF1E1E2A);
const _accent = Color(0xFF4ADE80);
const _accent2 = Color(0xFFA78BFA);
const _gold = Color(0xFFFBBF24);
const _muted = Color(0xFF6B6B80);
const _online = Color(0xFF60A5FA);
const _dlc = Color(0xFFF472B6);
const _platinum = Color(0xFFB9D7EA);

Color _phaseColor(String phase) {
  switch (phase) {
    case 'online':
      return _online;
    case 'dlc':
      return _dlc;
    default:
      return _accent;
  }
}

String? _phaseHint(String phase) {
  switch (phase) {
    case 'online':
      return 'Needs online or multiplayer play';
    case 'dlc':
      return 'May require DLC or expansion content';
    default:
      return null;
  }
}

Color _rarityColor(double? percent) {
  final p = percent ?? 100.0;
  if (p < 10) return _gold;
  if (p < 30) return const Color(0xFF94A3B8);
  return const Color(0xFFB4783C);
}

String _rarityName(double? percent) {
  final p = percent ?? 100.0;
  if (p < 10) return 'Gold';
  if (p < 30) return 'Silver';
  return 'Bronze';
}

String _pct(double v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%';

/// Fetches the guide and shows loading / error / the map.
class AchievementGuideScreen extends StatefulWidget {
  final int rawgId;
  final String gameName;

  final PlatinumSeenStore seenStore;

  const AchievementGuideScreen({
    super.key,
    required this.rawgId,
    required this.gameName,
    this.seenStore = const PlatinumSeenStore(),
  });

  @override
  State<AchievementGuideScreen> createState() => _AchievementGuideScreenState();
}

class _AchievementGuideScreenState extends State<AchievementGuideScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final gp = context.read<GameProvider>();
      final lp = context.read<LoggedGamesProvider>();
      await Future.wait([gp.getAchievementGuide(widget.rawgId), lp.loadFromBackend()]);
      if (!mounted) return;
      await _maybeCelebratePlatinum(gp, lp);
    });
  }

  // The first time the guide is opened after the Platinum is earned.
  Future<void> _maybeCelebratePlatinum(GameProvider gp, LoggedGamesProvider lp) async {
    final guide = gp.guide;
    final platinum = guide?.platinum;
    if (guide == null || platinum == null) return;
    if (!guide.platinumEarned(lp.earnedAchievementKeys(widget.rawgId))) return;
    if (!await widget.seenStore.markCelebrated(widget.rawgId) || !mounted) return;
    showPlatinumCelebration(context, gameName: widget.gameName, trophyName: platinum.name, image: platinum.image);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.watch<GameProvider>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: Text(
          '${widget.gameName} — Guide',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Recompute guide',
            icon: const Icon(Icons.refresh),
            onPressed: gp.isLoadingGuide
                ? null
                : () => context.read<GameProvider>().getAchievementGuide(
                      widget.rawgId,
                      refresh: true,
                    ),
          ),
        ],
      ),
      body: _buildBody(gp),
    );
  }

  Widget _buildBody(GameProvider gp) {
    if (gp.isLoadingGuide || gp.guideStatus == GameStatus.idle) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _accent2, strokeWidth: 2),
              SizedBox(height: 16),
              Text(
                'Building your trophy guide…',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                'The first time for a game can take up to a minute.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (gp.guideStatus == GameStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 12),
              Text(
                gp.errorMessage.isNotEmpty ? gp.errorMessage : 'Could not build a guide for this game.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => context.read<GameProvider>().getAchievementGuide(widget.rawgId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent2,
                  side: const BorderSide(color: _accent2),
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final guide = gp.guide;
    if (guide == null || guide.nodes.isEmpty) {
      return const Center(
        child: Text('No guide available for this game yet.', style: TextStyle(color: _muted, fontSize: 13)),
      );
    }
    final earned = context.watch<LoggedGamesProvider>().earnedAchievementKeys(widget.rawgId);
    return AchievementGuideView(guide: guide, earned: earned);
  }
}

class _PhaseTab {
  final String key;
  final String name;
  final int count;
  final int done;
  const _PhaseTab(this.key, this.name, this.count, this.done);
}

/// The winding map for an already-loaded guide. When the guide has more than
/// one phase (Base game / Online / DLC), each phase gets its own tab: the base
/// game shows first and the others are one tap away instead of far down the
/// page. Laddered trophies are one stacked node.
class AchievementGuideView extends StatefulWidget {
  final AchievementGuide guide;

  /// [trophyKey]s of achievements the user ticked in their logs.
  final Set<String> earned;

  const AchievementGuideView({super.key, required this.guide, this.earned = const {}});

  static const double nodeSize = 60;
  static const double labelSpace = 40;
  static const double verticalGap = 124;
  static const double topPad = 20;
  static const double hintHeight = 48;

  static Widget _avatar(String? image, double size, Color color, {double ring = 2}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55), width: ring),
      ),
      child: ClipOval(
        child: image != null
            ? CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => Center(child: Text('🏆', style: TextStyle(fontSize: size * 0.33))),
              )
            : Center(child: Text('🏆', style: TextStyle(fontSize: size * 0.33))),
      ),
    );
  }

  @override
  State<AchievementGuideView> createState() => _AchievementGuideViewState();
}

class _AchievementGuideViewState extends State<AchievementGuideView> {
  static const double nodeSize = AchievementGuideView.nodeSize;
  static const double labelSpace = AchievementGuideView.labelSpace;

  String? _selected;

  /// One tab per phase present on the path, base game first, named from the
  /// backend's phase list when it has an entry.
  List<_PhaseTab> _tabs() {
    final guide = widget.guide;
    final keys = <String>[];
    for (final n in guide.nodes) {
      if (!keys.contains(n.phase)) keys.add(n.phase);
    }
    if (keys.remove('base')) keys.insert(0, 'base');

    return keys.map((k) {
      final info = guide.phases.where((p) => p.key == k);
      final fallback = guide.nodes.firstWhere((n) => n.phase == k).phaseName;
      final name = info.isNotEmpty && info.first.name.isNotEmpty
          ? info.first.name
          : (fallback.isNotEmpty ? fallback : k);
      final inPhase = guide.nodes.where((n) => n.phase == k);
      return _PhaseTab(k, name, inPhase.length, inPhase.where((n) => n.isEarned(widget.earned)).length);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final progress = _buildProgress();
    if (!widget.guide.hasMultiplePhases || tabs.length < 2) {
      final map = _buildMap(_withPlatinum(widget.guide.nodes), null);
      if (progress == null) return map;
      return Column(children: [progress, Expanded(child: map)]);
    }

    final selected = tabs.any((t) => t.key == _selected) ? _selected! : tabs.first.key;
    final inPhase = widget.guide.nodes.where((n) => n.phase == selected).toList();
    final nodes = selected == 'base' ? _withPlatinum(inPhase) : inPhase;

    return Column(
      children: [
        ?progress,
        _buildTabBar(tabs, selected),
        Expanded(child: _buildMap(nodes, selected)),
      ],
    );
  }

  List<GuideNode> _withPlatinum(List<GuideNode> nodes) {
    final p = widget.guide.platinum;
    return p == null ? nodes : [...nodes, p];
  }

  bool _isEarned(GuideNode node) =>
      node.isPlatinum ? widget.guide.platinumEarned(widget.earned) : node.isEarned(widget.earned);

  /// "You've earned X of Y trophies", counted per real trophy (ladder tiers
  /// included). Hidden until the user has logged at least one.
  Widget? _buildProgress() {
    var total = 0;
    var done = 0;
    for (final n in widget.guide.nodes) {
      total += n.trophyNames.length;
      done += n.earnedCount(widget.earned);
    }
    if (done == 0 || total == 0) return null;

    return Padding(
      key: const Key('guide-progress'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, size: 14, color: _accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "You've earned $done of $total trophies",
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text('${(done * 100 / total).round()}%', style: const TextStyle(color: _accent, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 6,
              backgroundColor: _surface2,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<_PhaseTab> tabs, String selected) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final t = tabs[i];
          final active = t.key == selected;
          final color = _phaseColor(t.key);
          return GestureDetector(
            key: Key('guide-phase-${t.key}'),
            onTap: () => setState(() => _selected = t.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.18) : _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? color : _surface2, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.name,
                    style: TextStyle(
                      color: active ? color : Colors.white,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    t.done > 0 ? '${t.done}/${t.count}' : '${t.count}',
                    style: TextStyle(color: t.done == t.count ? _accent : _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHint(String phase, String hint) {
    final color = _phaseColor(phase);
    return Positioned(
      left: 16,
      right: 16,
      top: 8,
      child: Container(
        key: Key('guide-phase-hint-$phase'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(hint, style: const TextStyle(color: _muted, fontSize: 11.5))),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(List<GuideNode> nodes, String? phase) {
    final hint = phase == null ? null : _phaseHint(phase);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final centerX = width / 2;
        final amplitude = (width * 0.26).clamp(48.0, 120.0);

        final centers = <Offset>[];
        double y = AchievementGuideView.topPad + (hint != null ? AchievementGuideView.hintHeight : 0);
        for (int i = 0; i < nodes.length; i++) {
          centers.add(Offset(centerX + amplitude * sin(i * 1.05), y + nodeSize / 2));
          y += AchievementGuideView.verticalGap;
        }
        final totalHeight = y + 16;

        return SingleChildScrollView(
          // Each tab gets its own scroll view, so switching starts at the top.
          key: ValueKey('guide-map-${phase ?? 'all'}'),
          child: SizedBox(
            width: width,
            height: totalHeight,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(width, totalHeight),
                  painter: _GuidePathPainter(centers),
                ),
                if (hint != null) _buildHint(phase!, hint),
                for (int i = 0; i < nodes.length; i++) _buildNode(context, nodes[i], centers[i]),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNode(BuildContext context, GuideNode node, Offset center) {
    final earned = _isEarned(node);
    final color = node.isPlatinum ? _platinum : (earned ? _accent : _rarityColor(node.percent));
    const tileWidth = 124.0;
    final tiersDone = node.tiers
        .where((t) => t.trophies.isNotEmpty && t.trophies.every((tr) => widget.earned.contains(trophyKey(tr.name))))
        .length;

    return Positioned(
      left: center.dx - tileWidth / 2,
      top: center.dy - nodeSize / 2,
      width: tileWidth,
      height: nodeSize + labelSpace,
      child: GestureDetector(
        key: Key(node.isPlatinum ? 'guide-node-platinum' : 'guide-node-${node.order}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _showNodeSheet(context, node),
        child: Column(
          children: [
            SizedBox(
              width: nodeSize + 8,
              height: nodeSize,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (node.isLadder)
                    Positioned(
                      left: 10,
                      top: -4,
                      child: Container(
                        width: nodeSize,
                        height: nodeSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _surface2,
                          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
                        ),
                      ),
                    ),
                  AchievementGuideView._avatar(node.image, nodeSize, color, ring: 2),
                  Positioned(
                    right: 2,
                    top: -2,
                    child: _badge(
                      child: node.isPlatinum
                          ? const Icon(Icons.star, size: 11, color: _platinum)
                          : Text('${node.order}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (node.isLadder)
                    Positioned(
                      right: -2,
                      bottom: -4,
                      child: _badge(
                        wide: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.layers, size: 10, color: _accent2),
                            const SizedBox(width: 2),
                            Text(
                              tiersDone > 0 ? '$tiersDone/${node.tiers.length}' : '${node.tiers.length}',
                              style: TextStyle(color: tiersDone > 0 ? _accent : Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (node.hidden)
                    const Positioned(
                      left: 0,
                      bottom: -2,
                      child: _HiddenBadge(),
                    ),
                  if (earned)
                    const Positioned(
                      left: 0,
                      top: -2,
                      child: _EarnedBadge(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              node.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: node.isPlatinum ? _platinum : (earned ? _accent : Colors.white),
                fontSize: 11,
                height: 1.15,
                fontWeight: node.isPlatinum ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _badge({required Widget child, bool wide = false}) => Container(
        constraints: BoxConstraints(minWidth: 20, minHeight: 20, maxWidth: wide ? 52 : 20),
        padding: EdgeInsets.symmetric(horizontal: wide ? 4 : 0),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _bg, width: 2),
        ),
        child: wide ? FittedBox(fit: BoxFit.scaleDown, child: child) : child,
      );

  void _showNodeSheet(BuildContext context, GuideNode node) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => GuideNodeSheet(
        node: node,
        earned: widget.earned,
        platinumEarned: node.isPlatinum ? widget.guide.platinumEarned(widget.earned) : false,
        baseDone: node.isPlatinum ? widget.guide.baseNodes.where((n) => n.isEarned(widget.earned)).length : 0,
        baseTotal: node.isPlatinum ? widget.guide.baseNodes.length : 0,
      ),
    );
  }
}

class _HiddenBadge extends StatelessWidget {
  const _HiddenBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('guide-hidden-badge'),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: _surface2,
        shape: BoxShape.circle,
        border: Border.all(color: _bg, width: 2),
      ),
      child: const Icon(Icons.visibility_off, size: 11, color: _muted),
    );
  }
}

class _EarnedBadge extends StatelessWidget {
  const _EarnedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('guide-earned-badge'),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: _accent,
        shape: BoxShape.circle,
        border: Border.all(color: _bg, width: 2),
      ),
      child: const Icon(Icons.check, size: 12, color: _bg),
    );
  }
}

class _GuidePathPainter extends CustomPainter {
  final List<Offset> points;

  _GuidePathPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = _accent2.withValues(alpha: 0.35)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final midY = (prev.dy + curr.dy) / 2;
      path.cubicTo(prev.dx, midY, curr.dx, midY, curr.dx, curr.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GuidePathPainter old) => old.points != points;
}

/// Detail sheet for one stop: a single trophy, or a ladder with its tiers.
class GuideNodeSheet extends StatelessWidget {
  final GuideNode node;
  final Set<String> earned;

  // Platinum only: its earned state depends on the whole guide, not the node.
  final bool platinumEarned;
  final int baseDone;
  final int baseTotal;

  const GuideNodeSheet({
    super.key,
    required this.node,
    this.earned = const {},
    this.platinumEarned = false,
    this.baseDone = 0,
    this.baseTotal = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = node.isPlatinum ? _platinum : _rarityColor(node.percent);
    final isEarned = node.isPlatinum ? platinumEarned : node.isEarned(earned);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: _muted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AchievementGuideView._avatar(node.image, 48, color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.isPlatinum ? node.name : 'Step ${node.order}: ${node.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (node.isPlatinum) _chip('Platinum', _platinum, icon: Icons.star),
                          if (node.percent != null && !node.isPlatinum) _chip('${_rarityName(node.percent)} · ${_pct(node.percent!)}', color),
                          if (node.percent != null && node.isPlatinum) _chip(_pct(node.percent!), _platinum),
                          if (node.phase != 'base') _chip(node.phaseName.isNotEmpty ? node.phaseName : node.phase, _phaseColor(node.phase)),
                          if (node.hidden) _chip('Hidden', _muted, icon: Icons.visibility_off),
                          if (node.isLadder) _chip('${node.tiers.length} tiers', _accent2, icon: Icons.layers),
                          if (isEarned)
                            _chip('Earned', _accent, icon: Icons.check_circle)
                          else if (!node.isPlatinum && node.earnedCount(earned) > 0)
                            _chip('${node.earnedCount(earned)}/${node.trophyNames.length} earned', _accent, icon: Icons.check_circle_outline),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (node.isPlatinum)
              ..._platinumBody()
            else if (node.isLadder)
              ..._ladderBody()
            else
              ..._trophyBody(),
            if (node.suspectedCategory != null) _suspectedNote(),
          ],
        ),
      ),
    );
  }

  List<Widget> _trophyBody() => [
        if (node.description != null) ...[
          const SizedBox(height: 16),
          Text(node.description!, style: const TextStyle(color: _muted, fontSize: 13, height: 1.4)),
        ],
        if (node.steps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _steps(node.steps),
        ],
      ];

  List<Widget> _platinumBody() => [
        const SizedBox(height: 16),
        Text(
          node.description ?? 'The Platinum trophy: proof you finished the game.',
          style: const TextStyle(color: _muted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 10),
        const Text(
          'Unlocks automatically once you have earned every base-game trophy. DLC trophies are not needed.',
          style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
        ),
        if (baseTotal > 0) ...[
          const SizedBox(height: 14),
          Text(
            '$baseDone of $baseTotal base-game stops done',
            key: const Key('guide-platinum-progress'),
            style: const TextStyle(color: _platinum, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: baseDone / baseTotal,
              minHeight: 6,
              backgroundColor: _surface2,
              color: _platinum,
            ),
          ),
        ],
      ];

  List<Widget> _ladderBody() {
    return [
      const SizedBox(height: 18),
      const Text('Earn these in order', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      for (int i = 0; i < node.tiers.length; i++) _tierRow(node.tiers[i], last: i == node.tiers.length - 1),
    ];
  }

  Widget _tierRow(GuideTier tier, {required bool last}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  key: Key('guide-tier-${tier.label}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent2.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent2.withValues(alpha: 0.4)),
                  ),
                  child: Text(tier.label, style: const TextStyle(color: _accent2, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 4), color: _accent2.withValues(alpha: 0.25))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in tier.trophies)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (earned.contains(trophyKey(t.name))) ...[
                                const Icon(Icons.check_circle, size: 14, color: _accent),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(t.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                              if (t.rarity != null)
                                Text(_pct(t.rarity!), style: TextStyle(color: _rarityColor(t.rarity), fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          if (t.description != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(t.description!, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                            ),
                          if (t.steps.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: _steps(t.steps)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _steps(List<String> steps) {
    return Column(
      key: const Key('guide-steps'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.chevron_right, size: 14, color: _accent),
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.35))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _suspectedNote() {
    final label = node.suspectedCategory == 'dlc' ? 'DLC content' : 'online or multiplayer play';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        key: const Key('guide-suspected-note'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: _muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'This may need $label, but our data placed it in the base game.',
              style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _chip(String label, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 3)],
            Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
