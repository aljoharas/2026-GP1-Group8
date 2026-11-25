// Player Archetype from GET /users/me/archetype (your own: the full mix) or
// GET /users/:id/archetype (a friend's: name and description only).

class ArchetypeScore {
  final String archetype;
  final String description;
  final int percent;

  const ArchetypeScore({required this.archetype, required this.description, required this.percent});

  factory ArchetypeScore.fromJson(Map<String, dynamic> json) => ArchetypeScore(
        archetype: json['archetype'] as String? ?? '',
        description: json['description'] as String? ?? '',
        percent: (json['percent'] as num?)?.toInt() ?? 0,
      );
}

/// Two close types (within 10 points): shown as "`primary`, with a touch of `secondary`"
class ArchetypeBlend {
  final String primary;
  final String secondary;

  const ArchetypeBlend({required this.primary, required this.secondary});

  String get label => '$primary, with a touch of $secondary';

  static ArchetypeBlend? fromJson(Object? json) {
    if (json is! Map) return null;
    final p = json['primary'], s = json['secondary'];
    return p is String && s is String ? ArchetypeBlend(primary: p, secondary: s) : null;
  }
}

class Archetype {
  /// null when the user hasn't logged enough games yet
  final String? name;
  final String? description;

  /// Light / Committed / One-game; null for a model without families or a friend's view
  final String? family;

  /// Set when the top two types are within 10 points; never when [atypical]
  final ArchetypeBlend? blend;

  /// The user is far from every type: show "Closest match", no %, no blend
  final bool atypical;

  /// All six types, highest first, adding up to 100. Empty for a friend's view.
  final List<ArchetypeScore> scores;

  /// Two plain sentences about why. Empty for a friend's view.
  final List<String> reasons;
  final int gamesPlayed;
  final int minGames;

  const Archetype({
    this.name,
    this.description,
    this.family,
    this.blend,
    this.atypical = false,
    this.scores = const [],
    this.reasons = const [],
    this.gamesPlayed = 0,
    this.minGames = 5,
  });

  bool get isLocked => name == null;

  /// The top type's match %, or null when there are no scores (friend's view)
  int? get topPercent => scores.isEmpty ? null : scores.first.percent;

  factory Archetype.fromJson(Map<String, dynamic> json) {
    final scores = (json['scores'] as List? ?? [])
        .map((s) => ArchetypeScore.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList()
      // The server sorts already; sorting again keeps the bars right regardless
      ..sort((a, b) => b.percent.compareTo(a.percent));
    final atypical = json['atypical'] == true;
    return Archetype(
      name: json['archetype'] as String?,
      description: json['description'] as String?,
      family: json['family'] as String?,
      // The server already drops the blend for atypical users; this keeps the card right regardless
      blend: atypical ? null : ArchetypeBlend.fromJson(json['blend']),
      atypical: atypical,
      scores: scores,
      reasons: (json['reasons'] as List? ?? []).whereType<String>().toList(),
      gamesPlayed: (json['games_played'] as num?)?.toInt() ?? 0,
      minGames: (json['min_games'] as num?)?.toInt() ?? 5,
    );
  }
}
