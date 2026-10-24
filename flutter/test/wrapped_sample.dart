// Sample /users/me/wrapped data for cards 6–11, shared by the unit and golden
// tests. Image URLs are left out so tests never hit the network; the cards'
// placeholders (initials, trophy icon) show instead.

Map<String, dynamic> leaderboardEntry(String id, String name, num hours, int rank, {bool me = false}) => {
  'user_id': id,
  'username': name,
  'avatar_url': null,
  'hours': hours,
  'rank': rank,
  'is_me': me,
};

final List<Map<String, dynamic>> sampleTrophies = [
  for (final (i, (name, game, date)) in const [
    ('Lord of the Frenzied Flame', 'Elden Ring', '2026-05-02T18:20:00+03:00'),
    ('Shardbearer Malenia', 'Elden Ring', '2026-04-27T12:00:00+03:00'),
    ('Is There Anybody Out There?', 'Hades', '2026-04-11T12:00:00+03:00'),
    ('Pact of Punishment', 'Hades', '2026-03-30T12:00:00+03:00'),
    ('Farewell', 'Celeste', '2026-03-14T12:00:00+03:00'),
    ('Golden Strawberry', 'Celeste', '2026-03-02T12:00:00+03:00'),
    ('Speedrunner', 'Hollow Knight', '2026-02-20T12:00:00+03:00'),
    ('Completion', 'Hollow Knight', '2026-02-09T12:00:00+03:00'),
    ('Pure Completion', 'Hollow Knight', '2026-01-28T12:00:00+03:00'),
    ('Steel Soul', 'Hollow Knight', '2026-01-15T12:00:00+03:00'),
  ].indexed)
    {'achievement_id': i + 1, 'name': name, 'icon_url': null, 'game_name': game, 'unlocked_at': date},
];

Map<String, dynamic> sampleGame(int id, String name, num hours) => {
  'game_id': id,
  'name': name,
  'cover_image': null,
  'background_image': null,
  'hours': hours,
};

Map<String, dynamic> sampleWrappedJson() => {
  'year': 2026,
  'total_hours': 214.5,
  'games_played': 18,
  'games_played_covers': <String>[],
  'top_games': [sampleGame(1, 'Elden Ring', 96), sampleGame(2, 'Hades', 41.5), sampleGame(3, 'Celeste', 22)],
  'top_online_game': sampleGame(7, 'Valorant', 31),
  'me': {'user_id': 'u1', 'username': 'Aljohara', 'avatar_url': null},
  'trophies_earned': 14,
  'trophies': sampleTrophies,
  'play_style': {'personality': 'the_closer', 'finished': 9, 'paused': 2, 'playing': 3},
  'rating': {
    'rated_games': 11,
    'average': 7.4,
    'rater_type': 'tough_critic',
    'average_gap': -0.8,
    'breakdown': {'1': 0, '2': 0, '3': 1, '4': 0, '5': 1, '6': 2, '7': 3, '8': 2, '9': 1, '10': 1},
  },
  'friends_hours': {
    'user_rank': 2,
    'friends_beaten': 3,
    'friends_counted': 4,
    'leaderboard': [
      leaderboardEntry('u2', 'Sara', 240.5, 1),
      leaderboardEntry('u1', 'Aljohara', 214.5, 2, me: true),
      leaderboardEntry('u4', 'Reem', 120, 3),
      leaderboardEntry('u5', 'Dana', 64, 4),
      leaderboardEntry('u6', 'Lama', 12.5, 5),
    ],
  },
  'similar_friend': {
    'user_id': 'u3',
    'username': 'Nora',
    'avatar_url': null,
    'match_percent': 87,
    'shared_genres': ['RPG', 'Adventure'],
  },
};

/// Worst cases for layout: long names and titles, singular counts, a long
/// type name, a tie, no genres, no rater type, no trophy list.
Map<String, dynamic> stressWrappedJson() => {
  ...sampleWrappedJson(),
  'total_hours': 1,
  'games_played': 1,
  'top_games': [
    sampleGame(1, 'The Legend of Zelda: Tears of the Kingdom', 1),
    sampleGame(2, 'Warhammer 40,000: Space Marine 2', 0.5),
  ],
  'top_online_game': sampleGame(7, 'Counter-Strike: Global Offensive', 0.5),
  'me': {'user_id': 'u1', 'username': 'Abdulrahman_AlQahtani', 'avatar_url': null},
  'trophies_earned': 1,
  'trophies': <Map<String, dynamic>>[],
  'play_style': {'personality': 'forever_in_progress', 'finished': 0, 'paused': 0, 'playing': 1204},
  'rating': {
    'rated_games': 3,
    'average': 10,
    'rater_type': null,
    'average_gap': null,
    'breakdown': {'10': 3},
  },
  'friends_hours': {
    'user_rank': 1,
    'friends_beaten': 0,
    'friends_counted': 1,
    'leaderboard': [
      leaderboardEntry('u1', 'Abdulrahman_AlQahtani', 1204.5, 1, me: true),
      leaderboardEntry('u2', 'Maximilian_Featherstonehaugh', 1204.5, 1),
    ],
  },
  'similar_friend': {
    'user_id': 'u3',
    'username': 'Maximilian_Featherstonehaugh',
    'avatar_url': null,
    'match_percent': 100,
    'shared_genres': <String>[],
  },
};
