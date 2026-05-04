import 'package:flutter/material.dart';
import '../services/game_service.dart';

class LoggedGame {
  final int? entryId;
  final String name;
  final String? backgroundImage;
  final String? coverImage;
  final int? rawgId;
  final double? hoursPlayed;
  final String? comment;
  final List<String> achievements;
  final DateTime loggedAt;
  final bool isFinished;
  final bool isPaused;
  final String? platform;

  String? get displayImage => coverImage ?? backgroundImage;

  LoggedGame({
    this.entryId,
    required this.name,
    this.backgroundImage,
    this.coverImage,
    this.rawgId,
    this.hoursPlayed,
    this.comment,
    this.achievements = const [],
    required this.loggedAt,
    this.isFinished = false,
    this.isPaused = false,
    this.platform,
  });

  factory LoggedGame.fromJson(Map<String, dynamic> json) {
    return LoggedGame(
      entryId: json['id'] is int
          ? json['id'] as int
          : int.tryParse(json['id']?.toString() ?? ''),
      name: json['name'] as String? ?? 'Unknown Game',
      backgroundImage: json['background_image'] as String?,
      coverImage: json['cover_image'] as String?,
      rawgId: json['rawg_id'] is int
          ? json['rawg_id'] as int
          : int.tryParse(json['rawg_id']?.toString() ?? ''),
      hoursPlayed: json['hours_played'] != null
          ? double.tryParse(json['hours_played'].toString())
          : null,
      comment: json['comment'] as String?,
      achievements: (json['achievements'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      loggedAt: json['logged_at'] != null
          ? DateTime.tryParse(json['logged_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isFinished: json['is_finished'] == true,
      isPaused: json['is_paused'] == true,
      platform: json['platform_name'] as String?,
    );
  }
}

enum MyGamesSortOrder { date, name }

class LoggedGamesProvider extends ChangeNotifier {
  final _service = GameService();
  final List<LoggedGame> _games = [];
  MyGamesSortOrder _sortOrder = MyGamesSortOrder.date;
  bool _loaded = false;

  List<LoggedGame> get games {
    final sorted = List<LoggedGame>.from(_games);
    if (_sortOrder == MyGamesSortOrder.date) {
      sorted.sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    } else {
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return sorted;
  }

  MyGamesSortOrder get sortOrder => _sortOrder;

  int get distinctGameCount =>
      _games.map((g) => g.rawgId ?? g.name).toSet().length;

  List<LoggedGame> get myGames {
    final Map<Object, LoggedGame> byGame = {};
    for (final g in _games) {
      final key = g.rawgId ?? g.name as Object;
      if (!byGame.containsKey(key) ||
          g.loggedAt.isAfter(byGame[key]!.loggedAt)) {
        byGame[key] = g;
      }
    }
    return byGame.values.toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  List<LoggedGame> get currentlyPlaying {
    // First find the most recent entry per game, then keep only unfinished ones.
    // Without this, an older unfinished entry would keep showing a game that was
    // later re-logged as finished.
    final Map<Object, LoggedGame> latestByGame = {};
    for (final g in _games) {
      final key = g.rawgId ?? g.name as Object;
      if (!latestByGame.containsKey(key) ||
          g.loggedAt.isAfter(latestByGame[key]!.loggedAt)) {
        latestByGame[key] = g;
      }
    }
    return latestByGame.values
        .where((g) => !g.isFinished && !g.isPaused)
        .toList()
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
  }

  void setSortOrder(MyGamesSortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  void reset() {
    _games.clear();
    _loaded = false;
    notifyListeners();
  }

  // Load logged games from backend (called once when profile screen opens)
  Future<void> loadFromBackend() async {
    if (_loaded) return;
    try {
      final result = await _service.getLoggedGames();
      if (result['success'] == true) {
        final list = result['games'] as List<dynamic>? ?? [];
        _games.clear();
        for (final g in list) {
          _games.add(LoggedGame.fromJson(g as Map<String, dynamic>));
        }
        _loaded = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('LoggedGamesProvider.loadFromBackend error: $e');
    }
  }

  // Remove all logs for a game from the library
  Future<void> removeGame(int rawgId) async {
    _games.removeWhere((g) => g.rawgId == rawgId);
    notifyListeners();

    try {
      await _service.removeGame(rawgId: rawgId);
    } catch (e) {
      debugPrint('LoggedGamesProvider.removeGame error: $e');
    }
  }

  // Remove a single achievement from a specific log entry
  Future<void> removeAchievementFromEntry(int entryId, String achievementName) async {
    final index = _games.indexWhere((g) => g.entryId == entryId);
    if (index == -1) return;

    final entry = _games[index];
    final updated = entry.achievements.where((a) => a != achievementName).toList();
    _games[index] = LoggedGame(
      entryId: entry.entryId,
      name: entry.name,
      backgroundImage: entry.backgroundImage,
      coverImage: entry.coverImage,
      rawgId: entry.rawgId,
      hoursPlayed: entry.hoursPlayed,
      comment: entry.comment,
      achievements: updated,
      loggedAt: entry.loggedAt,
      isFinished: entry.isFinished,
      isPaused: entry.isPaused,
      platform: entry.platform,
    );
    notifyListeners();

    try {
      await _service.updateEntryAchievements(entryId, updated);
    } catch (e) {
      debugPrint('removeAchievementFromEntry error: $e');
    }
  }

  // Add a game locally and save to backend
  Future<void> addGame(LoggedGame game) async {
    // Optimistically update UI
    _games.add(game);
    notifyListeners();

    // Persist to backend
    if (game.rawgId != null) {
      try {
        await _service.logGame(
          rawgId: game.rawgId!,
          hoursPlayed: game.hoursPlayed,
          comment: game.comment,
          achievements: game.achievements,
          isFinished: game.isFinished,
          isPaused: game.isPaused,
          loggedAt: game.loggedAt,
          platformName: game.platform,
        );
      } catch (e) {
        debugPrint('LoggedGamesProvider.addGame backend error: $e');
      }
    }
  }
}
