import 'package:flutter/material.dart';

import '../models/archetype.dart';

// Player Archetype on a profile. Your own profile shows the top type with its
// match %, and taps open the full mix; a friend's profile shows only the name
// and description (the server never sends their scores or reasons).

const _surface = Color(0xFF16161E);
const _surface2 = Color(0xFF1E1E2A);
const _kText = Color(0xFFF0F0F0);
const _muted = Color(0xFF6B6B80);
const _border = Color(0x12FFFFFF);
const _accent = Color(0xFF4ADE80);

const _icons = {
  'Completionist': Icons.emoji_events_outlined,
  'Explorer': Icons.explore_outlined,
  'Competitor': Icons.sports_esports_outlined,
  'The Main': Icons.language,
  'Devotee': Icons.favorite_border,
  'Casual': Icons.weekend_outlined,
};

IconData archetypeIcon(String? name) => _icons[name] ?? Icons.auto_awesome_outlined;

class ArchetypeCard extends StatelessWidget {
  final Archetype? archetype;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  /// A friend's profile: name and description only, never tappable
  final bool friendView;

  /// Shown in the friend's locked state ("@sara hasn't ...")
  final String? username;

  const ArchetypeCard({
    super.key,
    this.archetype,
    this.loading = false,
    this.error,
    this.onRetry,
    this.friendView = false,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final a = archetype;
    final tappable = !friendView && !loading && error == null && a != null && !a.isLocked && a.scores.isNotEmpty;
    return Semantics(
      button: tappable,
      child: GestureDetector(
        onTap: tappable ? () => showArchetypeMixSheet(context, a) : null,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Badge(icon: _leadingIcon()),
              const SizedBox(width: 14),
              Expanded(child: _body()),
              if (tappable) const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Icon(Icons.chevron_right, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _leadingIcon() {
    if (loading) return Icons.hourglass_empty;
    if (error != null) return Icons.cloud_off_outlined;
    if (archetype == null || archetype!.isLocked) return Icons.lock_outline;
    return archetypeIcon(archetype!.name);
  }

  Widget _body() {
    final children = <Widget>[const _Label('PLAYER ARCHETYPE'), const SizedBox(height: 6)];
    final a = archetype;

    if (loading) {
      children.addAll(const [
        _Placeholder(width: 170, height: 18),
        SizedBox(height: 8),
        _Placeholder(width: 230, height: 12),
      ]);
    } else if (error != null) {
      children.add(Text(error!, style: const TextStyle(color: _kText, fontSize: 14, height: 1.35)));
      if (onRetry != null) {
        children.add(TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            foregroundColor: _accent,
          ),
          child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w600)),
        ));
      }
    } else if (a == null || a.isLocked) {
      if (friendView) {
        children.add(Text(
          username == null ? "Hasn't unlocked an archetype yet" : "@$username hasn't unlocked an archetype yet",
          style: const TextStyle(color: _muted, fontSize: 14),
        ));
      } else {
        children.addAll(_locked(a));
      }
    } else {
      final title = friendView || a.topPercent == null ? a.name! : '${a.name} · ${a.topPercent}% match';
      children.add(Text(title,
          style: const TextStyle(color: _kText, fontSize: 17, fontWeight: FontWeight.w700)));
      if ((a.description ?? '').isNotEmpty) {
        children.addAll([
          const SizedBox(height: 4),
          Text(a.description!, style: const TextStyle(color: _muted, fontSize: 13, height: 1.35)),
        ]);
      }
      if (!friendView && a.scores.isNotEmpty) {
        children.addAll(const [
          SizedBox(height: 10),
          Text('Tap to see your full mix',
              style: TextStyle(color: _accent, fontSize: 13, fontWeight: FontWeight.w600)),
        ]);
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  List<Widget> _locked(Archetype? a) {
    final played = a?.gamesPlayed ?? 0;
    final needed = a?.minGames ?? 5;
    return [
      const Text('Log a few more games to unlock your archetype',
          style: TextStyle(color: _kText, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: (played / needed).clamp(0, 1).toDouble(),
          minHeight: 6,
          backgroundColor: _surface2,
          valueColor: const AlwaysStoppedAnimation(_accent),
        ),
      ),
      const SizedBox(height: 6),
      Text('$played of $needed games logged',
          style: const TextStyle(color: _muted, fontSize: 12)),
    ];
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  const _Badge({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: _accent.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: _accent, size: 22),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2));
}

class _Placeholder extends StatelessWidget {
  final double width;
  final double height;
  const _Placeholder({required this.width, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(4)),
      );
}

// ── Full mix bottom sheet ────────────────────────────────────────────────────

Future<void> showArchetypeMixSheet(BuildContext context, Archetype archetype) => showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ArchetypeMixSheet(archetype: archetype),
    );

class ArchetypeMixSheet extends StatelessWidget {
  final Archetype archetype;
  const ArchetypeMixSheet({super.key, required this.archetype});

  @override
  Widget build(BuildContext context) {
    final a = archetype;
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
                  decoration: BoxDecoration(color: _muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 18),
              const _Label('YOUR PLAYSTYLE MIX'),
              const SizedBox(height: 6),
              Text('${a.name} · ${a.topPercent}% match',
                  style: const TextStyle(color: _kText, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Based on the ${a.gamesPlayed} games you\'ve logged',
                  style: const TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 20),
              for (final (i, s) in a.scores.indexed) _ScoreRow(score: s, top: i == 0),
              if (a.reasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('WHY ${a.name!.toUpperCase()}',
                    style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 10),
                for (final r in a.reasons) _Reason(text: r),
              ],
              const SizedBox(height: 14),
              const Text('Playstyles overlap, so most players are a mix of a few types.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final ArchetypeScore score;
  final bool top;
  const _ScoreRow({required this.score, required this.top});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${score.archetype}, ${score.percent} percent. ${score.description}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(archetypeIcon(score.archetype), size: 16, color: top ? _accent : _muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(score.archetype,
                      style: TextStyle(
                          color: _kText, fontSize: 15, fontWeight: top ? FontWeight.w700 : FontWeight.w500)),
                ),
                Text('${score.percent}%',
                    style: TextStyle(
                        color: _kText,
                        fontSize: 15,
                        fontWeight: top ? FontWeight.w700 : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (_, c) => Stack(
                children: [
                  Container(
                    height: 8,
                    width: c.maxWidth,
                    decoration: BoxDecoration(color: _surface2, borderRadius: BorderRadius.circular(4)),
                  ),
                  Container(
                    height: 8,
                    // A sliver stays visible at 0–1% so every type has a bar
                    width: (c.maxWidth * score.percent / 100).clamp(4.0, c.maxWidth).toDouble(),
                    decoration: BoxDecoration(
                      color: top ? _accent : _accent.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(score.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.check_circle_outline, size: 16, color: _accent),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(color: _kText, fontSize: 14, height: 1.4))),
          ],
        ),
      );
}
