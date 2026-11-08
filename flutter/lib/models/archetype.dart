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

class Archetype {
  /// null when the user hasn't logged enough games yet
  final String? name;
  final String? description;

  /// All six types, highest first, adding up to 100. Empty for a friend's view.
  final List<ArchetypeScore> scores;

  /// Two plain sentences about why. Empty for a friend's view.
  final List<String> reasons;
  final int gamesPlayed;
  final int minGames;

  const Archetype({
    this.name,
    this.description,
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
    return Archetype(
      name: json['archetype'] as String?,
      description: json['description'] as String?,
      scores: scores,
      reasons: (json['reasons'] as List? ?? []).whereType<String>().toList(),
      gamesPlayed: (json['games_played'] as num?)?.toInt() ?? 0,
      minGames: (json['min_games'] as num?)?.toInt() ?? 5,
    );
  }
}
