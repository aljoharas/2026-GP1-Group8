import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import 'log_game_detail_screen.dart';

class LogGameSearchScreen extends StatefulWidget {
  const LogGameSearchScreen({super.key});

  // In-memory recent searches (persists across pushes within the same session)
  static final List<String> recentSearches = [];

  @override
  State<LogGameSearchScreen> createState() => _LogGameSearchScreenState();
}

class _LogGameSearchScreenState extends State<LogGameSearchScreen> {
  final _searchCtrl = TextEditingController();

  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFF4ADE80);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameProvider>().clearSearch();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // rebuild to show/hide clear button
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _searchCtrl.text == value) {
        if (value.trim().isEmpty) {
          context.read<GameProvider>().clearSearch();
        } else {
          context.read<GameProvider>().searchGames(value);
        }
      }
    });
  }

  void _applyRecent(String query) {
    _searchCtrl.text = query;
    _searchCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    context.read<GameProvider>().searchGames(query);
    setState(() {});
  }

  void _addToRecent(String gameName) {
    LogGameSearchScreen.recentSearches.remove(gameName);
    LogGameSearchScreen.recentSearches.insert(0, gameName);
    if (LogGameSearchScreen.recentSearches.length > 10) {
      LogGameSearchScreen.recentSearches.removeLast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final games = context.watch<GameProvider>();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Cancel',
            style: TextStyle(color: muted, fontSize: 15),
          ),
        ),
        leadingWidth: 80,
        centerTitle: true,
        title: const Text(
          'Add a Game',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Name of game',
                hintStyle: const TextStyle(color: muted),
                prefixIcon: const Icon(Icons.search, color: muted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: muted),
                        onPressed: () {
                          _searchCtrl.clear();
                          context.read<GameProvider>().clearSearch();
                          setState(() {});
                        },
                      )
                    : null,
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),

          const Divider(height: 1, color: border),

          // Results / Recent searches
          Expanded(child: _buildBody(games)),
        ],
      ),
    );
  }

  Widget _buildBody(GameProvider games) {
    // Show recent searches when search bar is empty / idle
    if (_searchCtrl.text.trim().isEmpty ||
        games.searchStatus == GameStatus.idle) {
      if (_searchCtrl.text.trim().isEmpty) {
        return _buildRecentSearches();
      }
    }

    if (games.isSearching) {
      return const Center(
          child: CircularProgressIndicator(color: accent));
    }

    if (games.searchStatus == GameStatus.error) {
      return Center(
        child: Text(games.errorMessage,
            style: const TextStyle(color: muted)),
      );
    }

    if (games.searchResults.isEmpty &&
        games.searchStatus == GameStatus.success) {
      return const Center(
        child: Text('No games found',
            style: TextStyle(color: muted, fontSize: 15)),
      );
    }

    if (games.searchResults.isNotEmpty) {
      return ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: games.searchResults.length,
        itemBuilder: (context, index) =>
            _buildGameTile(games.searchResults[index]),
      );
    }

    return _buildRecentSearches();
  }

  Widget _buildRecentSearches() {
    final recents = LogGameSearchScreen.recentSearches;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recents.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RECENT SEARCHES',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(
                      () => LogGameSearchScreen.recentSearches.clear()),
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: recents.length,
              itemBuilder: (context, index) {
                final query = recents[index];
                return GestureDetector(
                  onTap: () => _applyRecent(query),
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: border)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: Row(children: [
                      const Icon(Icons.history, color: muted, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          query,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(
                            () => LogGameSearchScreen.recentSearches
                                .remove(query)),
                        child: const Icon(Icons.close,
                            color: muted, size: 16),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ] else ...[
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.sports_esports, color: muted, size: 48),
                  SizedBox(height: 12),
                  Text('Search for any game',
                      style: TextStyle(color: muted, fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGameTile(Map<String, dynamic> game) {
    return GestureDetector(
      onTap: () {
        _addToRecent(game['name'] ?? '');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LogGameDetailScreen(game: game),
          ),
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (game['cover_image'] ?? game['background_image']) != null
                ? Image.network(
                    game['cover_image'] ?? game['background_image'],
                    width: 56,
                    height: 72,
                    fit: BoxFit.cover,
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
                  game['name'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (game['released'] != null)
                  Text(
                    game['released'].toString().length >= 4
                        ? game['released'].toString().substring(0, 4)
                        : game['released'].toString(),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: muted, size: 20),
        ]),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 72,
      decoration: BoxDecoration(
        color: surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.sports_esports, color: muted, size: 24),
    );
  }
}
