import 'package:flutter/material.dart';

import '../models/archetype.dart';
import 'archetype_emblem.dart';

// Player Archetype as a small emblem badge next to the @handle, and the details
// sheet it opens. Your own profile shows the match % (and a blend or "closest
// match" when they apply); a friend's profile shows only the name, family and
// description, as the server sends nothing else.

const _badgeBg = Color(0xFF1F1F2B);
const _badgeBorder = Color(0xFF2E2E3E);
const _closestBg = Color(0xFF16161E);
const _dashed = Color(0xFF55556B);
const _sheetBg = Color(0xFF17171F);
const _sheetText = Color(0xFFF2F2F5);
const _sheetMuted = Color(0xFFA3A3B2);
const _track = Color(0xFF26263A);
const _minTap = 44.0;

int _gamesLeft(Archetype a) => (a.minGames - a.gamesPlayed).clamp(1, a.minGames).toInt();
String _games(int n) => n == 1 ? '1 more game' : '$n more games';

/// Tooltip text for the badge (long-press, or hover on web)
String archetypeBadgeTooltip(Archetype a, {bool friendView = false}) {
  if (a.isLocked) return 'Log ${_games(_gamesLeft(a))} to unlock your archetype';
  if (friendView || a.topPercent == null) return a.name!;
  if (a.atypical) return 'Closest match: ${a.name}';
  if (a.blend != null) return '${a.blend!.label} · ${a.topPercent}% match';
  return '${a.name} · ${a.topPercent}% match';
}

/// Screen-reader label for the badge
String archetypeBadgeSemantics(Archetype a, {bool friendView = false}) {
  if (a.isLocked) return 'Archetype locked: log ${_games(_gamesLeft(a))}';
  if (friendView || a.topPercent == null) return 'Archetype: ${a.name}. Double-tap for details';
  if (a.atypical) return 'Closest match: ${a.name}. Double-tap for details';
  if (a.blend != null) return 'Archetype: ${a.blend!.label}, ${a.topPercent}% match. Double-tap for details';
  return 'Archetype: ${a.name}, ${a.topPercent}% match. Double-tap for details';
}

class ArchetypeBadge extends StatelessWidget {
  final Archetype? archetype;
  final bool loading;

  /// Any error hides the badge: the profile shouldn't shout about it
  final String? error;

  /// A friend's profile: no %, no locked state (hidden instead)
  final bool friendView;

  const ArchetypeBadge({super.key, this.archetype, this.loading = false, this.error, this.friendView = false});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _HitArea(
        child: Semantics(
          label: 'Loading archetype',
          child: const SizedBox(
            width: 32,
            height: 30,
            child: DecoratedBox(
              decoration: BoxDecoration(color: _badgeBg, borderRadius: BorderRadius.all(Radius.circular(9))),
            ),
          ),
        ),
      );
    }
    final a = archetype;
    if (error != null || a == null) return const SizedBox.shrink();
    if (a.isLocked && friendView) return const SizedBox.shrink();

    final Widget content;
    final bool dashed;
    final Color background;
    if (a.isLocked) {
      dashed = true;
      background = _closestBg;
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_outline, size: 14, color: _sheetMuted),
        const SizedBox(width: 4),
        Text('${a.gamesPlayed}/${a.minGames}',
            style: const TextStyle(color: _sheetMuted, fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
      ]);
    } else if (a.atypical && !friendView) {
      dashed = true;
      background = _closestBg;
      content = ArchetypeEmblem(archetype: a.name!, size: 22, faded: true);
    } else if (a.blend != null && !friendView) {
      dashed = false;
      background = _badgeBg;
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        ArchetypeEmblem(archetype: a.blend!.primary, size: 22),
        const SizedBox(width: 3),
        ArchetypeEmblem(archetype: a.blend!.secondary, size: 16, opacity: 0.75),
      ]);
    } else {
      dashed = false;
      background = _badgeBg;
      content = ArchetypeEmblem(archetype: a.name!, size: 22);
    }

    final badge = CustomPaint(
      painter: dashed ? const _DashedBorderPainter(color: _dashed, radius: 9) : null,
      child: Container(
        key: const ValueKey('archetype-badge-visual'),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
          border: dashed ? null : Border.all(color: _badgeBorder),
        ),
        child: content,
      ),
    );

    return Semantics(
      button: true,
      label: archetypeBadgeSemantics(a, friendView: friendView),
      excludeSemantics: true,
      child: Tooltip(
        message: archetypeBadgeTooltip(a, friendView: friendView),
        triggerMode: TooltipTriggerMode.longPress,
        child: _HitArea(
          onTap: () => showArchetypeDetails(context, a, friendView: friendView),
          child: badge,
        ),
      ),
    );
  }
}

/// At least 44×44 to tap, without growing the badge itself
class _HitArea extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _HitArea({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        key: const ValueKey('archetype-badge'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: _minTap, minHeight: _minTap),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        ),
      );
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (double d = 0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color || old.radius != radius;
}

// ── Details sheet ─────────────────────────────────────────────────────────────

Future<void> showArchetypeDetails(BuildContext context, Archetype archetype, {bool friendView = false}) =>
    showModalBottomSheet(
      context: context,
      backgroundColor: _sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ArchetypeDetailsSheet(archetype: archetype, friendView: friendView),
    );

class ArchetypeDetailsSheet extends StatefulWidget {
  final Archetype archetype;
  final bool friendView;

  /// Start with the full mix open (screenshots and tests)
  final bool initiallyExpanded;

  const ArchetypeDetailsSheet({super.key, required this.archetype, this.friendView = false, this.initiallyExpanded = false});

  @override
  State<ArchetypeDetailsSheet> createState() => _ArchetypeDetailsSheetState();
}

class _ArchetypeDetailsSheetState extends State<ArchetypeDetailsSheet> {
  late bool _expanded = widget.initiallyExpanded;

  String? _description(String name) {
    for (final s in widget.archetype.scores) {
      if (s.archetype == name) return s.description;
    }
    return name == widget.archetype.name ? widget.archetype.description : null;
  }

  int? _percent(String name) {
    for (final s in widget.archetype.scores) {
      if (s.archetype == name) return s.percent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.archetype;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: _sheetMuted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              ...(a.isLocked
                  ? _locked(a)
                  : widget.friendView
                      ? _friend(a)
                      : a.atypical
                          ? _closest(a)
                          : a.blend != null
                              ? _blend(a)
                              : _normal(a)),
              if (!a.isLocked && !widget.friendView && a.scores.isNotEmpty) ...[
                const SizedBox(height: 20),
                _MixToggle(expanded: _expanded, onTap: () => setState(() => _expanded = !_expanded)),
                if (_expanded) ..._fullMix(a),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String text) =>
      Text(text, style: const TextStyle(color: _sheetText, fontSize: 20, fontWeight: FontWeight.w700, height: 1.25));

  Widget _body(String? text, {Color color = _sheetMuted}) => (text ?? '').isEmpty
      ? const SizedBox.shrink()
      : Text(text!, style: TextStyle(color: color, fontSize: 14, height: 1.45));

  Widget _family(Archetype a) {
    final label = familyLabel(a.family ?? archetypeFamily[a.name]);
    return label == null
        ? const SizedBox.shrink()
        : Text(label, style: TextStyle(color: archetypeColour(a.name), fontSize: 13, fontWeight: FontWeight.w600));
  }

  Widget _percentLine(int percent, String suffix, {Color? color}) => Text('$percent% $suffix',
      style: TextStyle(color: color ?? _sheetText, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5));

  List<Widget> _header(Archetype a, {bool faded = false}) => [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ArchetypeEmblem(archetype: a.name!, size: 56, faded: faded),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _title(faded ? 'Closest match: ${a.name}' : a.name!),
                const SizedBox(height: 3),
                _family(a),
              ]),
            ),
          ],
        ),
      ];

  List<Widget> _normal(Archetype a) => [
        ..._header(a),
        const SizedBox(height: 16),
        _percentLine(a.topPercent ?? 0, 'match'),
        const SizedBox(height: 8),
        _body(a.description),
      ];

  List<Widget> _friend(Archetype a) => [
        ..._header(a),
        const SizedBox(height: 14),
        _body(a.description),
      ];

  List<Widget> _closest(Archetype a) => [
        ..._header(a, faded: true),
        const SizedBox(height: 16),
        _percentLine(a.topPercent ?? 0, 'closest type', color: _sheetMuted),
        const SizedBox(height: 8),
        _body(a.description),
        const SizedBox(height: 12),
        const Text("Your playstyle doesn't closely match any one type yet.",
            style: TextStyle(color: _sheetText, fontSize: 14, fontWeight: FontWeight.w600, height: 1.45)),
      ];

  List<Widget> _blend(Archetype a) {
    final b = a.blend!;
    final p1 = _percent(b.primary), p2 = _percent(b.secondary);
    Widget part(String name, int? percent, double size, double opacity) => Row(mainAxisSize: MainAxisSize.min, children: [
          ArchetypeEmblem(archetype: name, size: size, opacity: opacity),
          const SizedBox(width: 8),
          Text('$name${percent == null ? '' : ' $percent%'}',
              style: const TextStyle(color: _sheetText, fontSize: 14, fontWeight: FontWeight.w600)),
        ]);
    Widget desc(String name) => Padding(
          padding: const EdgeInsets.only(top: 10),
          // Text.rich, not RichText: it inherits the app's text style (font family)
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$name: ', style: TextStyle(color: archetypeColour(name), fontWeight: FontWeight.w600)),
              TextSpan(text: _description(name) ?? ''),
            ]),
            style: const TextStyle(color: _sheetMuted, fontSize: 14, height: 1.45),
          ),
        );
    return [
      _title(b.label),
      const SizedBox(height: 3),
      _family(a),
      const SizedBox(height: 16),
      Wrap(spacing: 16, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        part(b.primary, p1, 56, 1),
        part(b.secondary, p2, 40, 0.75),
      ]),
      const SizedBox(height: 4),
      Semantics(
        label: '${b.primary} ${p1 ?? ''} percent, ${b.secondary} ${p2 ?? ''} percent',
        excludeSemantics: true,
        child: Text('${b.primary} ${p1 ?? '–'}% · ${b.secondary} ${p2 ?? '–'}%',
            style: const TextStyle(color: _sheetMuted, fontSize: 13)),
      ),
      desc(b.primary),
      desc(b.secondary),
    ];
  }

  List<Widget> _locked(Archetype a) {
    final left = _gamesLeft(a);
    return [
      Row(children: [
        CustomPaint(
          painter: const _DashedBorderPainter(color: _dashed, radius: 14),
          child: const SizedBox.square(dimension: 56, child: Icon(Icons.lock_outline, color: _sheetMuted, size: 26)),
        ),
        const SizedBox(width: 14),
        Expanded(child: _title('Log ${_games(left)} to unlock your archetype')),
      ]),
      const SizedBox(height: 18),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: (a.gamesPlayed / a.minGames).clamp(0, 1).toDouble(),
          minHeight: 6,
          backgroundColor: _track,
          valueColor: const AlwaysStoppedAnimation(kCommittedFamily),
        ),
      ),
      const SizedBox(height: 8),
      Text('${a.gamesPlayed}/${a.minGames} games logged', style: const TextStyle(color: _sheetMuted, fontSize: 13)),
    ];
  }

  List<Widget> _fullMix(Archetype a) => [
        const SizedBox(height: 14),
        for (final (i, s) in a.scores.indexed) _ScoreRow(score: s, top: i == 0),
        if (a.reasons.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('WHY ${a.name!.toUpperCase()}',
              style: const TextStyle(color: _sheetMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          for (final r in a.reasons) _Reason(text: r),
        ],
        const SizedBox(height: 6),
        const Text('Playstyles overlap, so most players are a mix of a few types.',
            style: TextStyle(color: _sheetMuted, fontSize: 12, height: 1.4)),
      ];
}

class _MixToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _MixToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        expanded: expanded,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: _minTap),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: _badgeBg, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Expanded(
                child: Text('See your full mix',
                    style: TextStyle(color: _sheetText, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, color: _sheetMuted),
            ]),
          ),
        ),
      );
}

// The full mix: one bar per type, highest first (from the former archetype card's sheet)
class _ScoreRow extends StatelessWidget {
  final ArchetypeScore score;
  final bool top;
  const _ScoreRow({required this.score, required this.top});

  @override
  Widget build(BuildContext context) {
    final colour = archetypeColour(score.archetype);
    return Semantics(
      label: '${score.archetype}, ${score.percent} percent. ${score.description}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              ArchetypeEmblem(archetype: score.archetype, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(score.archetype,
                    style: TextStyle(color: _sheetText, fontSize: 15, fontWeight: top ? FontWeight.w700 : FontWeight.w500)),
              ),
              Text('${score.percent}%',
                  style: TextStyle(
                      color: _sheetText,
                      fontSize: 15,
                      fontWeight: top ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (_, c) => Stack(children: [
                Container(
                  height: 8,
                  width: c.maxWidth,
                  decoration: BoxDecoration(color: _track, borderRadius: BorderRadius.circular(4)),
                ),
                Container(
                  height: 8,
                  // A sliver stays visible at 0–1% so every type has a bar
                  width: (c.maxWidth * score.percent / 100).clamp(4.0, c.maxWidth).toDouble(),
                  decoration: BoxDecoration(
                    color: top ? colour : colour.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Text(score.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _sheetMuted, fontSize: 12, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  final String text;
  const _Reason({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.check_circle_outline, size: 16, color: _sheetMuted),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: _sheetText, fontSize: 14, height: 1.4))),
        ]),
      );
}
