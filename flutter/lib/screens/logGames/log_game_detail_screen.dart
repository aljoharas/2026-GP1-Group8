import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/logged_games_provider.dart';

class LogGameDetailScreen extends StatefulWidget {
  final Map<String, dynamic> game;

  const LogGameDetailScreen({super.key, required this.game});

  @override
  State<LogGameDetailScreen> createState() => _LogGameDetailScreenState();
}

class _LogGameDetailScreenState extends State<LogGameDetailScreen> {
  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFF4ADE80);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);
  static const red     = Color(0xFFE8002D);

  List<String> get _availablePlatforms {
    final raw = widget.game['platforms'];

    // Flatten raw platform data into a list of name strings
    List<String> names = [];
    if (raw is List && raw.isNotEmpty) {
      for (final entry in raw) {
        if (entry is String) {
          names.add(entry);
        } else if (entry is Map) {
          final name = entry['platform'] is Map
              ? (entry['platform'] as Map)['name']?.toString()
              : entry['name']?.toString();
          if (name != null && name.isNotEmpty) names.add(name);
        }
      }
    }

    // Collapse into platform families
    final result = <String>[];
    final lower = names.map((n) => n.toLowerCase()).toList();

    if (lower.any((n) => n.contains('playstation') || n.startsWith('ps'))) {
      result.add('PlayStation');
    }
    if (lower.any((n) => n.contains('xbox'))) {
      result.add('Xbox');
    }
    if (lower.any((n) => n.contains('switch') || n.contains('nintendo'))) {
      result.add('Switch');
    }

    // PC is always available
    result.add('PC');

    return result;
  }

  final _hoursCtrl   = TextEditingController();
  final _commentCtrl = TextEditingController();
  final Set<int> _selectedAchievements = {};
  final Set<int> _previouslyEarnedIds = {};
  bool _isFinished = false;
  bool _isPaused = false;
  bool _achievementsExpanded = false;
  DateTime _loggedAt = DateTime.now();
  String? _selectedPlatform;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final rawgIdRaw = widget.game['rawg_id'] ?? widget.game['id'];
      final rawgId = rawgIdRaw is int
          ? rawgIdRaw
          : int.tryParse(rawgIdRaw?.toString() ?? '');
      if (rawgId == null || !mounted) return;

      // 1. Ensure logged games are in memory
      final lp = context.read<LoggedGamesProvider>();
      await lp.loadFromBackend();
      if (!mounted) return;

      // 2. Collect achievement names earned in previous logs for this game
      final prevEarned = <String>{};
      for (final g in lp.games) {
        if (g.rawgId == rawgId) prevEarned.addAll(g.achievements);
      }

      // 3. Fetch this game's achievements (awaited so data is ready)
      final gp = context.read<GameProvider>();
      await gp.getAchievements(rawgId);
      if (!mounted || prevEarned.isEmpty || gp.achievements.isEmpty) return;

      // 4. Mark achievements earned in previous logs as "previously earned"
      setState(() {
        for (int i = 0; i < gp.achievements.length; i++) {
          final a = gp.achievements[i] as Map<String, dynamic>;
          final achName = a['name'] as String?;
          final id = a['id'] as int? ?? i;
          if (achName != null && prevEarned.contains(achName)) {
            _previouslyEarnedIds.add(id);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Widget _platformIcon(String platform, bool selected) {
    final color = selected ? accent : muted;
    final lower = platform.toLowerCase();
    if (lower.contains('playstation') || lower.contains('ps')) {
      return FaIcon(FontAwesomeIcons.playstation, color: color, size: 18);
    } else if (lower.contains('xbox')) {
      return FaIcon(FontAwesomeIcons.xbox, color: color, size: 18);
    } else if (lower.contains('switch') || lower.contains('nintendo')) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CustomPaint(painter: _SwitchIconPainter(color)),
      );
    } else if (lower == 'pc' || lower.contains('windows') ||
               lower.contains('mac') || lower.contains('linux')) {
      return Icon(Icons.computer_outlined, color: color, size: 18);
    } else if (lower.contains('android') || lower.contains('ios') ||
               lower.contains('mobile')) {
      return Icon(Icons.smartphone_outlined, color: color, size: 18);
    }
    return Icon(Icons.sports_esports_outlined, color: color, size: 18);
  }

  void _toggleAchievement(int id) {
    if (_previouslyEarnedIds.contains(id)) return;
    setState(() {
      if (_selectedAchievements.contains(id)) {
        _selectedAchievements.remove(id);
      } else {
        _selectedAchievements.add(id);
      }
    });
  }

  bool _allSelected(GameProvider gp) {
    final eligible = gp.achievements.where((a) {
      final id = a['id'] as int? ?? gp.achievements.indexOf(a);
      return !_previouslyEarnedIds.contains(id);
    });
    if (eligible.isEmpty) return false;
    return eligible.every((a) {
      final id = a['id'] as int? ?? gp.achievements.indexOf(a);
      return _selectedAchievements.contains(id);
    });
  }

  void _toggleSelectAll(GameProvider gp) {
    final eligibleIds = gp.achievements
        .map((a) => a['id'] as int? ?? gp.achievements.indexOf(a))
        .where((id) => !_previouslyEarnedIds.contains(id))
        .toSet();

    if (_allSelected(gp)) {
      setState(() => _selectedAchievements.removeAll(eligibleIds));
    } else {
      setState(() => _selectedAchievements.addAll(eligibleIds));
      _showPlatinumPopup();
    }
  }

  void _showPlatinumPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('🏆', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            const Text(
              'Trophy Master!',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Wow, you collected ALL the trophies in ${widget.game['name'] ?? 'this game'}! That\'s legendary.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final hoursText = _hoursCtrl.text.trim();
    final hours = hoursText.isEmpty ? null : double.tryParse(hoursText);

    final gp = context.read<GameProvider>();
    final lp = context.read<LoggedGamesProvider>();

    final earned = gp.achievements
        .where((a) => _selectedAchievements.contains(a['id']))
        .map((a) => a['name'] as String)
        .toList();

    final rawgIdRaw = widget.game['rawg_id'] ?? widget.game['id'];
    final rawgId = rawgIdRaw is int
        ? rawgIdRaw
        : int.tryParse(rawgIdRaw?.toString() ?? '');

    lp.addGame(LoggedGame(
      name: widget.game['name'] as String? ?? 'Unknown Game',
      backgroundImage: widget.game['background_image'] as String?,
      coverImage: widget.game['cover_image'] as String?,
      rawgId: rawgId,
      hoursPlayed: hours,
      comment: _commentCtrl.text.trim().isEmpty
          ? null
          : _commentCtrl.text.trim(),
      achievements: earned,
      loggedAt: _loggedAt,
      isFinished: _isFinished,
      isPaused: _isPaused,
      platform: _selectedPlatform,
    ));

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Game Added!',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          '${widget.game['name']} has been added to your games.',
          style: const TextStyle(color: muted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Done', style: TextStyle(color: accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final game     = widget.game;
    final imageUrl = (game['cover_image'] ?? game['background_image']) as String?;
    final name     = (game['name'] ?? 'Unknown Game') as String;
    final gp       = context.watch<GameProvider>();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          'Log Game',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Game Card ──────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imageUrl != null
                      ? Image.network(
                          imageUrl,
                          width: 72, height: 96, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      if (game['released'] != null)
                        Text(
                          game['released'].toString().length >= 4
                              ? game['released'].toString().substring(0, 4)
                              : game['released'].toString(),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      if (game['rating'] != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.star,
                              color: Color(0xFFFBBF24), size: 13),
                          const SizedBox(width: 3),
                          Text('${game['rating']}',
                              style: const TextStyle(
                                  color: muted, fontSize: 12)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 28),

            // ── Achievements ───────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Achievements',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (gp.achievements.isNotEmpty)
                  GestureDetector(
                    onTap: () => _toggleSelectAll(gp),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 18, height: 18,
                          decoration: BoxDecoration(
                            color: _allSelected(gp) ? accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: _allSelected(gp) ? accent : muted,
                              width: 1.5,
                            ),
                          ),
                          child: _allSelected(gp)
                              ? const Icon(Icons.check, color: Colors.black, size: 12)
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _allSelected(gp) ? 'Deselect all' : 'Select all',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Select the achievements you have earned',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                if (_selectedAchievements.isNotEmpty) ...[
                  const Text('  ·  ', style: TextStyle(color: muted, fontSize: 12)),
                  Text(
                    '${_selectedAchievements.length} selected',
                    style: const TextStyle(color: accent, fontSize: 12),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            _buildAchievements(gp),

            const SizedBox(height: 28),

            // ── Hours Played ───────────────────────────────────────────────
            const Text(
              'Hours Played',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hoursCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. 42',
                hintStyle: const TextStyle(color: muted),
                suffixText: 'hrs',
                suffixStyle: const TextStyle(color: muted),
                filled: true,
                fillColor: surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
            ),

            const SizedBox(height: 28),

            // ── Comment ────────────────────────────────────────────────────
            const Text(
              'Comment',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Share your thoughts about this game',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'What did you think of this game?',
                hintStyle: const TextStyle(color: muted),
                filled: true,
                fillColor: surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: accent, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 28),

            // ── Status ────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isFinished = !_isFinished;
                      if (_isFinished) _isPaused = false;
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: _isFinished
                            ? accent.withValues(alpha: 0.08)
                            : surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isFinished
                              ? accent.withValues(alpha: 0.6)
                              : border,
                          width: _isFinished ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: _isFinished ? accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: _isFinished ? accent : muted,
                                width: 1.5,
                              ),
                            ),
                            child: _isFinished
                                ? const Icon(Icons.check,
                                    color: Colors.black, size: 13)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Finished',
                                  style: TextStyle(
                                      color: _isFinished ? accent : Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 1),
                              const Text('Completed',
                                  style: TextStyle(
                                      color: muted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isPaused = !_isPaused;
                      if (_isPaused) _isFinished = false;
                    }),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: _isPaused
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.08)
                            : surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isPaused
                              ? const Color(0xFFFBBF24).withValues(alpha: 0.6)
                              : border,
                          width: _isPaused ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: _isPaused
                                  ? const Color(0xFFFBBF24)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: _isPaused
                                    ? const Color(0xFFFBBF24)
                                    : muted,
                                width: 1.5,
                              ),
                            ),
                            child: _isPaused
                                ? const Icon(Icons.pause,
                                    color: Colors.black, size: 13)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Paused',
                                  style: TextStyle(
                                      color: _isPaused
                                          ? const Color(0xFFFBBF24)
                                          : Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 1),
                              const Text('On hold',
                                  style: TextStyle(
                                      color: muted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Platform ───────────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Platform',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'optional',
                      style: TextStyle(
                        color: muted.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availablePlatforms.map((p) {
                    final selected = _selectedPlatform == p;
                    final label = p;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedPlatform = selected ? null : p;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withValues(alpha: 0.12)
                              : surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? accent : border,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _platformIcon(p, selected),
                            const SizedBox(width: 7),
                            Text(
                              label,
                              style: TextStyle(
                                color: selected ? accent : Colors.white,
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Date ───────────────────────────────────────────────────────
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _loggedAt,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: accent,
                        onPrimary: Colors.black,
                        surface: surface,
                        onSurface: Colors.white,
                      ),
                      dialogTheme: const DialogThemeData(backgroundColor: surface),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) setState(() => _loggedAt = picked);
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, color: muted, size: 18),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Date Logged',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${_loggedAt.day}/${_loggedAt.month}/${_loggedAt.year}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: muted, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── Submit ─────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Add to My Games',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievements(GameProvider gp) {
    if (gp.isLoadingAchievements) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: accent),
        ),
      );
    }

    if (gp.achievementsStatus == GameStatus.error) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: const Center(
          child: Text(
            'Could not load achievements.\nMake sure the /games/:id/achievements\nendpoint is added to your backend.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 13, height: 1.6),
          ),
        ),
      );
    }

    if (gp.achievements.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: const Center(
          child: Text(
            'No achievements found for this game',
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ),
      );
    }

    const previewCount = 3;
    final all = gp.achievements;
    final visible = _achievementsExpanded ? all : all.take(previewCount).toList();
    final hiddenCount = all.length - previewCount;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          ...List.generate(visible.length, (i) {
            final a          = visible[i] as Map<String, dynamic>;
            final id         = a['id'] as int? ?? i;
            final isPrev     = _previouslyEarnedIds.contains(id);
            final selected   = _selectedAchievements.contains(id);
            final isChecked  = isPrev || selected;
            final isLast     = i == visible.length - 1 && (hiddenCount <= 0 || _achievementsExpanded);

            final checkColor = isPrev ? muted : accent;
            final nameColor  = isPrev ? muted : (selected ? accent : Colors.white);

            return Column(children: [
              GestureDetector(
                onTap: () => _toggleAchievement(id),
                child: Container(
                  color: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    if (a['image'] != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          a['image'],
                          width: 44, height: 44, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _achPlaceholder(),
                        ),
                      )
                    else
                      _achPlaceholder(),

                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a['name'] ?? '',
                            style: TextStyle(
                              color: nameColor,
                              fontSize: 13,
                              fontWeight: isChecked ? FontWeight.w700 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isPrev) ...[
                            const SizedBox(height: 3),
                            const Text(
                              'Earned in a previous log',
                              style: TextStyle(color: muted, fontSize: 10),
                            ),
                          ] else ...[
                            if (a['description'] != null &&
                                (a['description'] as String).isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                a['description'],
                                style: const TextStyle(color: muted, fontSize: 11),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (a['percent'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${a['percent']}% of players',
                                style: const TextStyle(color: muted, fontSize: 10),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: isChecked ? checkColor.withValues(alpha: isPrev ? 0.3 : 1.0) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isChecked ? checkColor : muted,
                          width: 1.5,
                        ),
                      ),
                      child: isChecked
                          ? Icon(Icons.check, color: isPrev ? muted : Colors.black, size: 14)
                          : null,
                    ),
                  ]),
                ),
              ),
              if (!isLast) const Divider(height: 1, color: border),
            ]);
          }),

          if (all.length > previewCount)
            GestureDetector(
              onTap: () => setState(() => _achievementsExpanded = !_achievementsExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _achievementsExpanded
                          ? 'Show less'
                          : 'Show $hiddenCount more',
                      style: const TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _achievementsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: accent, size: 18,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _achPlaceholder() {
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.military_tech, color: muted, size: 22),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 72, height: 96,
      decoration: BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.sports_esports, color: muted, size: 28),
    );
  }
}

class _SwitchIconPainter extends CustomPainter {
  final Color color;
  const _SwitchIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;

    // Left Joy-Con
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.08, w * 0.30, h * 0.84),
        Radius.circular(w * 0.15),
      ),
      paint,
    );

    // Screen body (center bar)
    canvas.drawRect(
      Rect.fromLTWH(w * 0.30, h * 0.22, w * 0.40, h * 0.56),
      paint,
    );

    // Right Joy-Con
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.70, h * 0.08, w * 0.30, h * 0.84),
        Radius.circular(w * 0.15),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SwitchIconPainter old) => old.color != color;
}
