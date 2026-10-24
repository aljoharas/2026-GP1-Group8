// Gaming Wrapped response from GET /users/me/wrapped. Every card field is
// nullable: a card with nothing to show comes back null and is skipped.

class WrappedGame {
  final int gameId;
  final String name;
  final String? coverImage;
  final String? backgroundImage;
  final double hours;

  const WrappedGame({
    required this.gameId,
    required this.name,
    this.coverImage,
    this.backgroundImage,
    required this.hours,
  });

  factory WrappedGame.fromJson(Map<String, dynamic> json) => WrappedGame(
        gameId: (json['game_id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        coverImage: _url(json['cover_image']),
        backgroundImage: _url(json['background_image']),
        hours: (json['hours'] as num?)?.toDouble() ?? 0,
      );
}

/// A person on a social card: the user ("me") or a friend.
class WrappedUser {
  final String userId;
  final String? username;
  final String? avatarUrl;

  const WrappedUser({required this.userId, this.username, this.avatarUrl});

  factory WrappedUser.fromJson(Map<String, dynamic> json) => WrappedUser(
        userId: json['user_id'] as String? ?? '',
        username: _text(json['username']),
        avatarUrl: _url(json['avatar_url']),
      );
}

class WrappedTrophy {
  final int achievementId;
  final String name;
  final String? iconUrl;
  final String? gameName;
  final DateTime? unlockedAt;

  const WrappedTrophy({
    required this.achievementId,
    required this.name,
    this.iconUrl,
    this.gameName,
    this.unlockedAt,
  });

  factory WrappedTrophy.fromJson(Map<String, dynamic> json) => WrappedTrophy(
        achievementId: (json['achievement_id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        iconUrl: _url(json['icon_url']),
        gameName: _text(json['game_name']),
        unlockedAt: DateTime.tryParse(json['unlocked_at'] as String? ?? ''),
      );
}

/// Card 7's types. Unknown keys from the server parse to null.
enum PlayerType {
  creditsChaser('credits_chaser'),
  foreverInProgress('forever_in_progress'),
  theCloser('the_closer'),
  theJuggler('the_juggler'),
  saveAndQuit('save_and_quit');

  final String key;

  const PlayerType(this.key);

  static PlayerType? fromKey(Object? key) => values.where((t) => t.key == key).firstOrNull;
}

/// How the year's games ended up: each game is in exactly one group.
class WrappedPlayStyle {
  final PlayerType? type;
  final int finished;
  final int paused;
  final int playing;

  const WrappedPlayStyle({this.type, this.finished = 0, this.paused = 0, this.playing = 0});

  int get total => finished + paused + playing;

  factory WrappedPlayStyle.fromJson(Map<String, dynamic> json) => WrappedPlayStyle(
        type: PlayerType.fromKey(json['personality']),
        finished: (json['finished'] as num?)?.toInt() ?? 0,
        paused: (json['paused'] as num?)?.toInt() ?? 0,
        playing: (json['playing'] as num?)?.toInt() ?? 0,
      );
}

enum RaterType {
  toughCritic('tough_critic'),
  fairJudge('fair_judge'),
  generousCritic('generous_critic');

  final String key;

  const RaterType(this.key);

  static RaterType? fromKey(Object? key) => values.where((t) => t.key == key).firstOrNull;
}

/// Ratings are out of 10; the card shows them as 5 stars.
class WrappedRating {
  final int ratedGames;
  final double average;
  final RaterType? raterType;

  /// The user's average minus other players', in stars (negative = harsher).
  final double? averageGap;

  /// How many rated games got each score, keyed 1–10.
  final Map<int, int> breakdown;

  const WrappedRating({
    required this.ratedGames,
    required this.average,
    this.raterType,
    this.averageGap,
    this.breakdown = const {},
  });

  double get averageStars => average / 2;

  /// Games per star row, index 0 = 1★: row n★ holds scores 2n−1 and 2n.
  List<int> get starCounts => [
        for (var n = 1; n <= 5; n++) (breakdown[2 * n - 1] ?? 0) + (breakdown[2 * n] ?? 0),
      ];

  factory WrappedRating.fromJson(Map<String, dynamic> json) {
    final breakdown = json['breakdown'] as Map<String, dynamic>? ?? const {};
    return WrappedRating(
      ratedGames: (json['rated_games'] as num?)?.toInt() ?? 0,
      average: (json['average'] as num?)?.toDouble() ?? 0,
      raterType: RaterType.fromKey(json['rater_type']),
      averageGap: (json['average_gap'] as num?)?.toDouble(),
      breakdown: {
        for (final MapEntry(:key, :value) in breakdown.entries) ?int.tryParse(key): (value as num?)?.toInt() ?? 0,
      },
    );
  }
}

class WrappedLeaderboardEntry {
  final WrappedUser user;
  final double hours;
  final int rank;
  final bool isMe;

  const WrappedLeaderboardEntry({required this.user, required this.hours, required this.rank, this.isMe = false});

  factory WrappedLeaderboardEntry.fromJson(Map<String, dynamic> json) => WrappedLeaderboardEntry(
        user: WrappedUser.fromJson(json),
        hours: (json['hours'] as num?)?.toDouble() ?? 0,
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        isMe: json['is_me'] as bool? ?? false,
      );
}

class WrappedFriendsHours {
  final int userRank;
  final int friendsBeaten;
  final int friendsCounted;

  /// Most hours first.
  final List<WrappedLeaderboardEntry> leaderboard;

  const WrappedFriendsHours({
    required this.userRank,
    required this.friendsBeaten,
    required this.friendsCounted,
    this.leaderboard = const [],
  });

  WrappedLeaderboardEntry? get me => leaderboard.where((e) => e.isMe).firstOrNull;

  /// The friend with the most hours: the leader, or the runner-up when the
  /// user is #1.
  WrappedLeaderboardEntry? get rival {
    WrappedLeaderboardEntry? best;
    for (final entry in leaderboard) {
      if (!entry.isMe && (best == null || entry.hours > best.hours)) best = entry;
    }
    return best;
  }

  factory WrappedFriendsHours.fromJson(Map<String, dynamic> json) => WrappedFriendsHours(
        userRank: (json['user_rank'] as num?)?.toInt() ?? 0,
        friendsBeaten: (json['friends_beaten'] as num?)?.toInt() ?? 0,
        friendsCounted: (json['friends_counted'] as num?)?.toInt() ?? 0,
        leaderboard: [
          for (final entry in json['leaderboard'] as List? ?? const [])
            WrappedLeaderboardEntry.fromJson(entry as Map<String, dynamic>),
        ],
      );
}

class WrappedSimilarFriend {
  final WrappedUser user;
  final int matchPercent;
  final List<String> sharedGenres;

  const WrappedSimilarFriend({required this.user, required this.matchPercent, this.sharedGenres = const []});

  factory WrappedSimilarFriend.fromJson(Map<String, dynamic> json) => WrappedSimilarFriend(
        user: WrappedUser.fromJson(json),
        matchPercent: (json['match_percent'] as num?)?.toInt() ?? 0,
        sharedGenres: [for (final genre in json['shared_genres'] as List? ?? const []) ?_text(genre)],
      );
}

class WrappedResponse {
  final int year;

  /// True before the year's Wrapped is released to this user; every card
  /// field is then null.
  final bool locked;
  final DateTime? releaseDate;
  final bool isPartial;
  final double? totalHours;
  final int? gamesPlayed;
  final List<String> gamesPlayedCovers;
  final List<WrappedGame>? topGames;
  final WrappedGame? topOnlineGame;
  final WrappedUser? me;
  final int? trophiesEarned;

  /// Newest first.
  final List<WrappedTrophy> trophies;
  final WrappedPlayStyle? playStyle;
  final WrappedRating? rating;
  final WrappedFriendsHours? friendsHours;
  final WrappedSimilarFriend? similarFriend;

  const WrappedResponse({
    required this.year,
    this.locked = false,
    this.releaseDate,
    this.isPartial = false,
    this.totalHours,
    this.gamesPlayed,
    this.gamesPlayedCovers = const [],
    this.topGames,
    this.topOnlineGame,
    this.me,
    this.trophiesEarned,
    this.trophies = const [],
    this.playStyle,
    this.rating,
    this.friendsHours,
    this.similarFriend,
  });

  factory WrappedResponse.fromJson(Map<String, dynamic> json) {
    final topGames = json['top_games'] as List?;
    final topOnline = json['top_online_game'] as Map<String, dynamic>?;
    return WrappedResponse(
      year: (json['year'] as num).toInt(),
      locked: json['locked'] as bool? ?? false,
      releaseDate: DateTime.tryParse(json['release_date'] as String? ?? ''),
      isPartial: json['is_partial'] as bool? ?? false,
      totalHours: (json['total_hours'] as num?)?.toDouble(),
      gamesPlayed: (json['games_played'] as num?)?.toInt(),
      gamesPlayedCovers: [
        for (final cover in json['games_played_covers'] as List? ?? const []) ?_url(cover),
      ],
      topGames: topGames?.map((g) => WrappedGame.fromJson(g as Map<String, dynamic>)).toList(),
      topOnlineGame: topOnline == null ? null : WrappedGame.fromJson(topOnline),
      me: _parse(json['me'], WrappedUser.fromJson),
      trophiesEarned: (json['trophies_earned'] as num?)?.toInt(),
      trophies: [
        for (final trophy in json['trophies'] as List? ?? const [])
          WrappedTrophy.fromJson(trophy as Map<String, dynamic>),
      ],
      playStyle: _parse(json['play_style'], WrappedPlayStyle.fromJson),
      rating: _parse(json['rating'], WrappedRating.fromJson),
      friendsHours: _parse(json['friends_hours'], WrappedFriendsHours.fromJson),
      similarFriend: _parse(json['similar_friend'], WrappedSimilarFriend.fromJson),
    );
  }
}

T? _parse<T>(Object? raw, T Function(Map<String, dynamic>) fromJson) =>
    raw is Map<String, dynamic> ? fromJson(raw) : null;

// Blank strings count as missing.
String? _text(Object? raw) => raw is String && raw.trim().isNotEmpty ? raw : null;

// Blank strings count as no image.
String? _url(Object? raw) => _text(raw);
