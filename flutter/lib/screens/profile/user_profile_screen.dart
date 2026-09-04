import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/sticky_tab_bar.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../services/auth_service.dart';
import '../../services/game_service.dart';
import '../../services/list_service.dart';
import '../friends/friends_screen.dart';
import '../game/game_profile_screen.dart';
import '../game/game_search_screen.dart';
import '../home/home_screen.dart';
import '../logGames/log_game_search_screen.dart';
import 'list_detail_screen.dart';
import 'list_editor_sheet.dart';
import 'privacy_policy_screen.dart';
import '../../providers/logged_games_provider.dart';
import 'settings_screen.dart';
import 'help_center_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final Set<String> _expandedJournalGames = {};
  final Map<String, Map<String, dynamic>> _resolved = {};

  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const accent = Color(0xFFE8002D);
  // Confirming that something worked is green; red stays on the action that
  // does the deleting, not on the receipt for it.
  static const successGreen = Color(0xFF4ADE80);
  static const gold = Color(0xFFF5C842);
  static const kText = Color(0xFFF0F0F0);
  static const muted = Color(0xFF6B6B80);
  static const border = Color(0x12FFFFFF);

  final _currentlyPlaying = [
    {'title': 'RESIDENT\nEVIL 4', 'name': 'Resident Evil 4', 'color': Color(0xFFE8002D)},
    {'title': 'SILENT\nHILL 2', 'name': 'Silent Hill 2', 'color': Color(0xFF93C5FD)},
    {'title': 'ELDEN\nRING', 'name': 'Elden Ring', 'color': Color(0xFF34D399)},
    {'title': 'GTA VI', 'name': 'Grand Theft Auto VI', 'color': Color(0xFFFBBF24)},
    {'title': 'GOD OF\nWAR', 'name': 'God of War (2018)', 'color': Color(0xFFFB923C)},
  ];

  List<Map<String, dynamic>> _favorites = [];
  int _friendsCount = 0;

  List<Map<String, dynamic>> _lists = [];
  bool _listsLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveAll();
      context.read<LoggedGamesProvider>().loadFromBackend();
      _loadFavorites();
      _loadFriendsCount();
      _loadLists();
    });
  }

  Future<void> _resolveAll() async {
    final gp = context.read<GameProvider>();
    final allNames = <String>{};
    for (final g in _currentlyPlaying) allNames.add(g['name'] as String);
    final futures = allNames.map((name) async {
      if (_resolved.containsKey(name)) return;
      final data = await gp.searchGameForId(name);
      if (data != null && mounted) setState(() => _resolved[name] = data);
    });
    await Future.wait(futures);
  }

  Future<void> _loadFavorites() async {
    final result = await GameService().getFavorites();
    if (result['success'] == true && mounted) {
      setState(() {
        _favorites = List<Map<String, dynamic>>.from(result['favorites'] ?? []);
      });
    }
  }

  // ── Lists ─────────────────────────────────────────────────────────────────

  Future<void> _loadLists() async {
    final result = await ListService().getLists();
    if (!mounted) return;
    setState(() {
      _lists = List<Map<String, dynamic>>.from(result['lists'] ?? []);
      _listsLoading = false;
    });
  }

  /// Plain dark toast for problems; green for "that worked". Only the
  /// confirmation is green — the button that did the deleting stays red.
  void _toast(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: TextStyle(
                color: success ? Colors.black : Colors.white,
                fontWeight: success ? FontWeight.w600 : FontWeight.normal)),
        backgroundColor: success ? successGreen : surface2,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createList() async {
    final result = await showListEditor(context, title: 'New List');
    if (result == null) return;

    final response = await ListService().createList(
      name: result.name,
      emoji: result.emoji,
      isPublic: result.isPublic,
    );
    if (response['success'] == true) {
      await _loadLists();
      _toast('List created successfully', success: true);
    } else {
      _toast(response['message'] ?? 'Could not create list');
    }
  }

  Future<void> _editList(Map<String, dynamic> list) async {
    final result = await showListEditor(
      context,
      title: 'Edit List',
      name: list['name'] as String,
      emoji: list['emoji'] as String,
      isPublic: list['is_public'] == true,
    );
    if (result == null) return;

    final response = await ListService().updateList(
      list['id'] as int,
      name: result.name,
      emoji: result.emoji,
      isPublic: result.isPublic,
    );
    if (response['success'] == true) {
      await _loadLists();
      _toast('List edited successfully', success: true);
    } else {
      _toast(response['message'] ?? 'Could not update list');
    }
  }

  Future<void> _deleteList(Map<String, dynamic> list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface2,
        title: Text('Delete "${list['name']}"?',
            style: const TextStyle(color: kText, fontSize: 17)),
        content: const Text(
          'The list and everything in it will be removed. This cannot be undone.',
          style: TextStyle(color: muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: accent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final response = await ListService().deleteList(list['id'] as int);
    if (response['success'] == true) {
      await _loadLists();
      _toast('List deleted successfully', success: true);
    } else {
      _toast(response['message'] ?? 'Could not delete list');
    }
  }

  /// Opens the list's own page; refetches only if something changed in there.
  Future<void> _openList(Map<String, dynamic> list) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ListDetailScreen(list: list)),
    );
    if (changed == true) await _loadLists();
  }

  Future<void> _loadFriendsCount() async {
    final count = await GameService().getFriendsCount();
    if (mounted) setState(() => _friendsCount = count);
  }

  Widget _buildFavoritesScroll() {
    if (_favorites.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(
          'Heart a game to add it here.',
          style: TextStyle(color: Color(0xFF6B6B80), fontSize: 13),
        ),
      );
    }
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 18, top: 12),
        itemCount: _favorites.length,
        itemBuilder: (_, i) {
          final g = _favorites[i];
          final name = g['name'] as String? ?? '';
          final imageUrl = (g['cover_image'] ?? g['background_image']) as String?;
          final rawgId = g['rawg_id'];
          return GestureDetector(
            onTap: () {
              if (rawgId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameProfileScreen(
                      rawgId: rawgId is int ? rawgId : int.parse(rawgId.toString()),
                      gameName: name,
                    ),
                  ),
                );
              }
            },
            child: Container(
              width: 90,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFF1E1E2E),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl != null
                    ? CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover)
                    : Center(
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white70),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _goToGame(String name) {
    final rawgId = _resolved[name]?['rawgId'];
    if (rawgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading game info, please try again...'),
          backgroundColor: Color(0xFF1E1E2A),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameProfileScreen(rawgId: rawgId as int, gameName: name),
      ),
    );
  }

  void _sprint2(String label) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text('🚧', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 12),
            Text('$label coming in GP2!',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('This feature is on its way.',
                style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── Edit profile sheet ────────────────────────────────────────────────────
  void _openEditProfile(
    BuildContext context,
    String currentUsername,
    String currentBio,
    String? currentAvatarUrl,
  ) {
    final usernameCtrl = TextEditingController(text: currentUsername);
    final bioCtrl = TextEditingController(text: currentBio);
    bool saving = false;
    String? errorText;
    XFile? newImage;
    String? previewUrl = currentAvatarUrl;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: muted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Edit Profile',
                      style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close, color: muted, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Avatar picker ─────────────────────────────────────────────
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();

                  ImageSource? source;
                  await showDialog(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      backgroundColor: const Color(0xFF16161E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Profile Picture',
                          style: TextStyle(
                              color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
                            title: const Text('Choose from library',
                                style: TextStyle(color: Colors.white)),
                            onTap: () {
                              source = ImageSource.gallery;
                              Navigator.pop(dctx);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.camera_alt_outlined, color: Colors.white),
                            title: const Text('Take a photo',
                                style: TextStyle(color: Colors.white)),
                            onTap: () {
                              source = ImageSource.camera;
                              Navigator.pop(dctx);
                            },
                          ),
                        ],
                      ),
                    ),
                  );

                  if (source == null) return;

                  final picked = await picker.pickImage(
                    source: source!,
                    maxWidth: 512, maxHeight: 512, imageQuality: 85,
                  );

                  if (picked != null) {
                    setSheetState(() {
                      newImage = picked;
                      previewUrl = null;
                    });
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: surface2,
                      backgroundImage: newImage != null
                          ? FileImage(File(newImage!.path))
                          : previewUrl != null
                              ? CachedNetworkImageProvider(previewUrl!)
                              : null,
                      child: (newImage == null && previewUrl == null)
                          ? const Icon(Icons.person_outline, size: 36, color: muted)
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: accent, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              const Text('Tap to change photo',
                  style: TextStyle(color: muted, fontSize: 11)),
              const SizedBox(height: 20),

              // Username field
              _editField(usernameCtrl, 'Username', Icons.person_outline, maxLength: 20),
              if (errorText != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        errorText!,
                        style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),

              // Bio field
              _editField(bioCtrl, 'Bio', Icons.edit_outlined,
                  maxLines: 3, maxLength: 150, hint: 'Tell us about yourself...'),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final newUsername = usernameCtrl.text.trim();
                          if (newUsername.isEmpty) {
                            setSheetState(() => errorText = 'Username is required');
                            return;
                          }
                          if (newUsername.length < 3) {
                            setSheetState(() => errorText =
                                'Username must be at least 3 characters');
                            return;
                          }

                          setSheetState(() { saving = true; errorText = null; });
                          final auth = context.read<AuthProvider>();
                          final token = await _getToken();
                          if (token == null) {
                            setSheetState(() => saving = false);
                            Navigator.pop(ctx);
                            return;
                          }

                          String? newAvatarUrl;
                          if (newImage != null) {
                            newAvatarUrl = await AuthService()
                                .uploadToCloudinary(newImage!.path);
                            if (newAvatarUrl == null) {
                              setSheetState(() {
                                saving = false;
                                errorText = 'Image upload failed. Please try again.';
                              });
                              return;
                            }
                          }

                          final error = await auth.updateProfile(
                            username: newUsername,
                            bio: bioCtrl.text.trim(),
                            token: token,
                            avatarUrl: newAvatarUrl,
                          );

                          if (error == null) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated! ✅'),
                                backgroundColor: Color(0xFF4ADE80),
                              ),
                            );
                          } else {
                            setSheetState(() {
                              saving = false;
                              errorText = error;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save Changes',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _getToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      return await user.getIdToken();
    } catch (_) {
      return null;
    }
  }

  Widget _editField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    int? maxLength,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          maxLength: maxLength,
          style: const TextStyle(color: kText, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint ?? label,
            hintStyle: const TextStyle(color: muted, fontSize: 14),
            prefixIcon: maxLines == 1 ? Icon(icon, color: muted, size: 18) : null,
            filled: true,
            fillColor: surface,
            counterStyle: const TextStyle(color: muted, fontSize: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: accent, width: 1.5)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ── Dots menu ─────────────────────────────────────────────────────────────
  void _openDotsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: muted.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _menuItem(Icons.settings_outlined, 'Settings', () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }),
              _menuDivider(),
              _menuItem(Icons.help_outline, 'Help Center', () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HelpCenterScreen()));
              }),
              _menuDivider(),
              _menuItem(Icons.shield_outlined, 'Privacy & Legal', () {
                Navigator.pop(context);
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap,
      {String? sub, bool isMuted = false}) {
    return ListTile(
      leading: Icon(icon, color: isMuted ? muted : kText, size: 22),
      title: Text(label,
          style: TextStyle(
              color: isMuted ? muted : kText,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
      subtitle: sub != null
          ? Text(sub, style: const TextStyle(color: muted, fontSize: 12))
          : null,
      onTap: onTap,
    );
  }

  Widget _menuDivider() => const Divider(color: border, height: 1, indent: 56);

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final lp = context.watch<LoggedGamesProvider>();
    final user = auth.currentUser;
    final username = user?['username'] as String? ?? 'Player';
    final bio = user?['bio'] as String? ?? '';
    final avatarUrl = user?['avatar_url'] as String?;
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: bg,
      body: DefaultTabController(
        length: 2,
        child: Stack(
          children: [
            RefreshIndicator(
              color: const Color(0xFF4ADE80),
              backgroundColor: surface,
              onRefresh: _refresh,
              notificationPredicate: (n) => n.depth == 2,
              child: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                SliverToBoxAdapter(
                  child: _buildProfileHeader(
                    username, bio, avatarUrl, topPad, lp),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: StickyTabBar(
                    TabBar(
                      indicatorColor: accent,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelColor: kText,
                      unselectedLabelColor: muted,
                      labelStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                      unselectedLabelStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                      tabs: const [
                        Tab(text: 'Overview'),
                        Tab(text: 'Journal'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _buildOverviewTab(),
                  _buildJournalTab(lp.games),
                ],
              ),
            ),
            ),
            Positioned(
                bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<LoggedGamesProvider>().loadFromBackend(),
      _loadFavorites(),
    ]);
  }

  // ── Profile Header (shared above both tabs) ───────────────────────────────
  Widget _buildProfileHeader(
    String username,
    String bio,
    String? avatarUrl,
    double topPad,
    LoggedGamesProvider lp,
  ) {
    return Padding(
      padding: EdgeInsets.only(top: topPad, left: 18, right: 18, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Top bar: dots menu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 40),
              GestureDetector(
                onTap: () => _openDotsMenu(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: List.generate(
                      3,
                      (_) => Container(
                        margin: const EdgeInsets.only(left: 5),
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Avatar row + edit button
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => _openEditProfile(
                    context, username, bio, avatarUrl),
                child: Stack(
                  children: [
                    Container(
                      width: 82, height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: border, width: 2),
                      ),
                      child: ClipOval(
                        child: avatarUrl != null
                            ? CachedNetworkImage(
                                imageUrl: avatarUrl,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  color: surface2,
                                  child: const Icon(Icons.person_outline,
                                      size: 36, color: muted),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: surface2,
                                  child: const Center(
                                    child: Text('🎮',
                                        style: TextStyle(fontSize: 36)),
                                  ),
                                ),
                              )
                            : Container(
                                color: surface2,
                                child: const Center(
                                  child: Text('🎮',
                                      style: TextStyle(fontSize: 36)),
                                ),
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 24, height: 24,
                        decoration: const BoxDecoration(
                            color: accent, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _openEditProfile(
                    context, username, bio, avatarUrl),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border),
                  ),
                  child: const Text('Edit Profile',
                      style: TextStyle(
                          color: kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(username,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kText,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text('@${username.toLowerCase().replaceAll(' ', '_')}',
              style: const TextStyle(fontSize: 12, color: muted)),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(bio,
                style: const TextStyle(
                    color: Color(0xCCF0F0F0), fontSize: 13, height: 1.5)),
          ] else ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () =>
                  _openEditProfile(context, username, bio, avatarUrl),
              child: const Text('+ Add a bio',
                  style: TextStyle(
                      color: muted,
                      fontSize: 13,
                      fontStyle: FontStyle.italic)),
            ),
          ],
          const SizedBox(height: 16),
          _buildFollowRow(),
          const SizedBox(height: 20),
          _buildStatsGrid(lp),
          const SizedBox(height: 16),
          _buildTrophyButton(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ── Overview Tab ──────────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    final lp = context.read<LoggedGamesProvider>();
    final playing = lp.currentlyPlaying;
    final myGames = lp.myGames;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      children: [
        _sectionHeader('Currently Playing', 'See All', onAction: playing.isEmpty ? null : () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _MyGamesAllScreen(
              games: playing, title: 'Currently Playing', showPausedFilter: false),
          ));
        }),
        if (playing.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text('Log a game to see it here',
                style: const TextStyle(color: muted, fontSize: 13)),
          )
        else
          _buildCurrentlyPlayingScroll(playing),
        const SizedBox(height: 24),
        _sectionHeader('My Games', 'See All', onAction: myGames.isEmpty ? null : () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _MyGamesAllScreen(games: myGames, title: 'My Games'),
          ));
        }),
        if (myGames.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text('Log a game to see it here',
                style: const TextStyle(color: muted, fontSize: 13)),
          )
        else
          _buildMyGamesScroll(myGames),
        const SizedBox(height: 24),
        _sectionHeader('Favorite Games', 'See All', onAction: _favorites.isEmpty ? null : () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => _FavoritesAllScreen(favorites: _favorites),
          ));
        }),
        _buildFavoritesScroll(),
        const SizedBox(height: 24),
        _sectionHeader('My Lists', '+ New List', onAction: _createList),
        const SizedBox(height: 8),
        if (_listsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text('Loading lists...',
                style: TextStyle(color: muted, fontSize: 13)),
          )
        else if (_lists.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text('Make a list to group games your own way',
                style: TextStyle(color: muted, fontSize: 13)),
          )
        else
          ..._lists.map(
            (list) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
              child: _buildListCard(list),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Journal Tab ───────────────────────────────────────────────────────────
  Widget _buildJournalTab(List<LoggedGame> games) {
    if (games.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border),
              ),
              child: const Icon(Icons.menu_book_outlined,
                  color: muted, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('No entries yet',
                style: TextStyle(
                    color: kText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Log a game to start your journal',
                style: TextStyle(color: muted, fontSize: 13)),
          ],
        ),
      );
    }

    // Group by rawgId (null keys grouped by name)
    final Map<String, List<LoggedGame>> grouped = {};
    final List<String> order = [];
    for (final g in games) {
      final key = g.rawgId?.toString() ?? g.name;
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        order.add(key);
      }
      grouped[key]!.add(g);
    }

    // Sort games by their most recent entry, newest first.
    order.sort((a, b) {
      final aLatest = grouped[a]!
          .map((e) => e.loggedAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      final bLatest = grouped[b]!
          .map((e) => e.loggedAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      return bLatest.compareTo(aLatest);
    });

    const limit = 10;
    final hasMore = order.length > limit;
    final visibleOrder = hasMore ? order.take(limit).toList() : order;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemCount: visibleOrder.length + (hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (hasMore && i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Row(children: [
              const Text('Recent',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _JournalAllScreen(games: games),
                  ),
                ),
                behavior: HitTestBehavior.opaque,
                child: const Text('See All',
                    style: TextStyle(fontSize: 13, color: muted)),
              ),
            ]),
          );
        }
        final key = visibleOrder[hasMore ? i - 1 : i];
        final entries = grouped[key]!;
        final rep = entries.reduce(
            (a, b) => a.loggedAt.isAfter(b.loggedAt) ? a : b);
        final isExpanded = _expandedJournalGames.contains(key);

        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Column(
              children: [
                // Game header row
                GestureDetector(
                  onTap: () => setState(() {
                    isExpanded
                        ? _expandedJournalGames.remove(key)
                        : _expandedJournalGames.add(key);
                  }),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 44, height: 58,
                            child: rep.displayImage != null
                                ? Image.network(
                                    rep.displayImage!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _journalThumb(),
                                  )
                                : _journalThumb(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(rep.name,
                                  style: const TextStyle(
                                      color: kText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Text(
                                '${entries.length} ${entries.length == 1 ? "entry" : "entries"}',
                                style: const TextStyle(
                                    color: muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: Icon(Icons.chevron_right,
                              color: isExpanded ? accent : muted),
                        ),
                      ],
                    ),
                  ),
                ),
                // Expandable log entries
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    children: [
                      const Divider(color: border, height: 1),
                      ...entries.map((e) => _buildJournalEntry(e)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _journalThumb() => Container(
        color: surface2,
        child: const Icon(Icons.sports_esports, color: muted, size: 20),
      );

  Widget _buildJournalEntry(LoggedGame entry) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = entry.loggedAt;
    final dateStr = '${months[d.month - 1]} ${d.day}, ${d.year}';

    return GestureDetector(
      onTap: () {
        if (entry.rawgId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GameProfileScreen(
                  rawgId: entry.rawgId!, gameName: entry.name),
            ),
          );
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: muted, size: 12),
                const SizedBox(width: 4),
                Text(dateStr,
                    style: const TextStyle(color: muted, fontSize: 11)),
                if (entry.hoursPlayed != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.access_time, color: muted, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.hoursPlayed!.toStringAsFixed(entry.hoursPlayed! % 1 == 0 ? 0 : 1)} hrs',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
                if (entry.achievements.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.military_tech_outlined,
                      color: muted, size: 12),
                  const SizedBox(width: 4),
                  Text('${entry.achievements.length}',
                      style: const TextStyle(color: muted, fontSize: 11)),
                ],
                if (entry.platform != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.videogame_asset_outlined,
                      color: muted, size: 12),
                  const SizedBox(width: 4),
                  Text(entry.platform!,
                      style: const TextStyle(color: muted, fontSize: 11)),
                ],
              ],
            ),
            if (entry.comment != null && entry.comment!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(entry.comment!,
                  style: const TextStyle(
                      color: Color(0xCCF0F0F0),
                      fontSize: 12,
                      height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            if (entry.achievements.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: entry.achievements.map((a) {
                  return GestureDetector(
                    onTap: entry.entryId == null ? null : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF16161E),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          title: const Text('Remove trophy?',
                              style: TextStyle(
                                  color: Color(0xFFF0F0F0),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          content: Text(
                            '"$a" will be removed from this log entry.',
                            style: const TextStyle(
                                color: Color(0xFF6B6B80), fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel',
                                  style: TextStyle(color: Color(0xFF6B6B80))),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Remove',
                                  style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        context
                            .read<LoggedGamesProvider>()
                            .removeAchievementFromEntry(entry.entryId!, a);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.only(
                          left: 8, top: 3, bottom: 3, right: 4),
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: gold.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a,
                              style: const TextStyle(
                                  color: gold,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(width: 4),
                          const Icon(Icons.close,
                              size: 10, color: gold),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Friends Row ───────────────────────────────────────────────────────────
  Widget _buildFollowRow() {
    return Column(
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen(initialTab: 1)))
                  .then((_) {
                // The count can change while they're in there (accepting a
                // request, removing someone), so re-read it on the way back.
                if (mounted) _loadFriendsCount();
              }),
              behavior: HitTestBehavior.opaque,
              child: _followItem('$_friendsCount', 'Friends', false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: border, height: 1),
      ],
    );
  }

  Widget _followItem(String num, String label, bool active) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(num,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: kText)),
      const SizedBox(height: 2),
      Text(label,
          style: TextStyle(
              fontSize: 12,
              color: active ? accent : muted,
              decoration: active ? TextDecoration.underline : null,
              decorationColor: accent)),
    ],
  );

  // ── Stats ─────────────────────────────────────────────────────────────────
  Widget _buildStatsGrid(LoggedGamesProvider lp) {
    final games = lp.games;
    final totalHours =
        games.fold<double>(0, (sum, g) => sum + (g.hoursPlayed ?? 0));
    final Map<Object, Set<String>> trophiesByGame = {};
    for (final g in games) {
      final key = g.rawgId ?? g.name;
      trophiesByGame.putIfAbsent(key, () => {}).addAll(g.achievements);
    }
    final totalTrophies =
        trophiesByGame.values.fold<int>(0, (sum, s) => sum + s.length);
    final hoursStr = totalHours == 0
        ? '0'
        : totalHours >= 1000
            ? '${(totalHours / 1000).toStringAsFixed(1)}K'
            : totalHours % 1 == 0
                ? totalHours.toInt().toString()
                : totalHours.toStringAsFixed(1);

    return Row(
      children: [
        Expanded(child: _statCard(hoursStr, 'HOURS PLAYED')),
        const SizedBox(width: 10),
        Expanded(child: _statCard('${lp.distinctGameCount}', 'GAMES PLAYED')),
        const SizedBox(width: 10),
        Expanded(child: _statCard('$totalTrophies', 'TROPHIES')),
      ],
    );
  }

  Widget _statCard(String val, String label) => Container(
    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: border),
    ),
    child: Column(
      children: [
        Text(val,
            style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800, color: kText)),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(
                fontSize: 9, color: muted, letterSpacing: 0.4)),
      ],
    ),
  );

  // ── Trophy Button ─────────────────────────────────────────────────────────
  Widget _buildTrophyButton() => GestureDetector(
    onTap: () => _sprint2('Trophy Guide'),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2A2200), bg]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
            child: const Center(
                child: Text('🏆', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trophy Guide',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kText)),
              SizedBox(height: 2),
              Text('View tips & unlock strategies',
                  style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.chevron_right, color: muted),
        ],
      ),
    ),
  );

  // ── Section Header ────────────────────────────────────────────────────────
  void _showDeletePicker(List<LoggedGame> games) {
    final unique = <int, LoggedGame>{};
    for (final g in games) {
      if (g.rawgId != null) unique.putIfAbsent(g.rawgId!, () => g);
    }
    final list = unique.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: muted, borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Remove a game',
                  style: TextStyle(color: kText, fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Divider(color: border),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.45,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.isEmpty ? 1 : list.length,
                itemBuilder: (_, i) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No games to remove', style: TextStyle(color: muted)),
                    );
                  }
                  final game = list[i];
                  return ListTile(
                    leading: game.displayImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              game.displayImage!,
                              width: 36, height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.sports_esports, color: muted, size: 28),
                            ),
                          )
                        : const Icon(Icons.sports_esports, color: muted, size: 28),
                    title: Text(game.name,
                        style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.delete_outline, color: accent, size: 20),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete(game);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(LoggedGame game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove game?',
            style: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'All logs for "${game.name}" will be permanently deleted.',
          style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<LoggedGamesProvider>().removeGame(game.rawgId!);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                // Green needs dark content text to stay readable.
                content: Text('"${game.name}" removed from your library',
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w600)),
                backgroundColor: successGreen,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ));
            },
            child: const Text('Remove',
                style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String action,
          {List<Map<String, dynamic>>? games, List<LoggedGame>? deletable, VoidCallback? onAction}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: kText)),
            const Spacer(),
            if (deletable != null && deletable.isNotEmpty)
              GestureDetector(
                onTap: () => _showDeletePicker(deletable),
                child: const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(Icons.delete_outline, color: muted, size: 18),
                ),
              ),
            GestureDetector(
              onTap: () {
                if (onAction != null) {
                  onAction();
                } else if (games != null) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _AllGamesScreen(
                          title: title,
                          games: games,
                          resolved: _resolved,
                          onTap: _goToGame,
                        ),
                      ));
                } else {
                  _sprint2(action);
                }
              },
              child: Text(action,
                  style: const TextStyle(fontSize: 13, color: muted)),
            ),
          ],
        ),
      );

  // ── Horizontal Scroll ─────────────────────────────────────────────────────
  Widget _buildCurrentlyPlayingScroll(List<LoggedGame> games) => SizedBox(
    height: 130,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 18, top: 12),
      itemCount: games.length,
      itemBuilder: (_, i) {
        final g = games[i];
        return GestureDetector(
          onTap: () {
            if (g.rawgId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GameProfileScreen(
                      rawgId: g.rawgId!, gameName: g.name),
                ),
              );
            }
          },
          child: Container(
            width: 90,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10), color: surface2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: g.displayImage != null
                  ? Image.network(g.displayImage!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _currentlyPlayingPlaceholder(g.name))
                  : _currentlyPlayingPlaceholder(g.name),
            ),
          ),
        );
      },
    ),
  );

  // ── My Games Scroll (with Paused label below poster) ─────────────────────
  Widget _buildMyGamesScroll(List<LoggedGame> games) => SizedBox(
    height: 155,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 18, top: 12),
      itemCount: games.length,
      itemBuilder: (_, i) {
        final g = games[i];
        return GestureDetector(
          onTap: () {
            if (g.rawgId != null) {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => GameProfileScreen(rawgId: g.rawgId!, gameName: g.name),
              ));
            }
          },
          child: SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 90, height: 120,
                      child: ColoredBox(
                        color: surface2,
                        child: g.displayImage != null
                            ? Image.network(g.displayImage!, fit: BoxFit.cover,
                                width: double.infinity, height: double.infinity,
                                errorBuilder: (_, __, ___) =>
                                    _currentlyPlayingPlaceholder(g.name))
                            : _currentlyPlayingPlaceholder(g.name),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 22,
                    child: g.isPaused
                        ? Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.pause,
                                      color: Color(0xFFFBBF24), size: 9),
                                  SizedBox(width: 3),
                                  Text('Paused',
                                      style: TextStyle(
                                          color: Color(0xFFFBBF24),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _currentlyPlayingPlaceholder(String name) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [surface2, surface],
      ),
    ),
    child: Center(
      child: Text(name,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: kText,
              letterSpacing: 0.3,
              height: 1.3),
          maxLines: 3,
          overflow: TextOverflow.ellipsis),
    ),
  );

  // ── List Card ─────────────────────────────────────────────────────────────
  Widget _buildListCard(Map<String, dynamic> list) {
    final games = List<Map<String, dynamic>>.from(list['games'] ?? []);
    final isPublic = list['is_public'] == true;
    return GestureDetector(
      onTap: () => _openList(list),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Text(list['emoji'] as String,
                style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(list['name'] as String,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kText)),
                    if (isPublic) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.public, size: 13, color: muted),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                    games.length == 1 ? '1 game' : '${games.length} games',
                    style: const TextStyle(fontSize: 12, color: muted)),
              ],
            ),
            const Spacer(),
            PopupMenuButton<String>(
              color: surface2,
              icon: const Icon(Icons.more_horiz, color: muted, size: 20),
              onSelected: (value) {
                if (value == 'edit') _editList(list);
                if (value == 'delete') _deleteList(list);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit list',
                      style: TextStyle(color: kText, fontSize: 14)),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete list',
                      style: TextStyle(color: accent, fontSize: 14)),
                ),
              ],
            ),
            const Icon(Icons.chevron_right, color: muted),
          ],
        ),
      ),
    );
  }

  // ── Bottom Nav ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.only(
          top: 12, bottom: bottomPad > 0 ? bottomPad : 14),
      decoration: const BoxDecoration(
        color: Color(0xF70E0E12),
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _navBtn(
            CustomPaint(
                size: const Size(22, 22), painter: _HomePainter(false)),
            () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const HomeScreen())),
          ),
          _navBtn(
            CustomPaint(
                size: const Size(22, 22), painter: _SearchPainter(false)),
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GameSearchScreen())),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const LogGameSearchScreen())),
            child: Container(
              width: 46, height: 46,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: const BoxDecoration(
                  color: accent, shape: BoxShape.circle),
              child: CustomPaint(painter: _PlusPainter()),
            ),
          ),
          _navBtn(
            CustomPaint(
                size: const Size(22, 22),
                painter: _FriendsPainter(false)),
            () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const FriendsScreen())),
          ),
          _navBtn(
            CustomPaint(
                size: const Size(22, 22),
                painter: _ProfilePainter(true)),
            () {},
          ),
        ],
      ),
    );
  }

  Widget _navBtn(Widget child, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: child,
    ),
  );
}

// ── My Games All Screen ───────────────────────────────────────────────────────
class _MyGamesAllScreen extends StatefulWidget {
  final List<LoggedGame> games;
  final String title;
  final bool showPausedFilter;
  const _MyGamesAllScreen({
    required this.games,
    this.title = 'My Games',
    this.showPausedFilter = true,
  });

  @override
  State<_MyGamesAllScreen> createState() => _MyGamesAllScreenState();
}

class _MyGamesAllScreenState extends State<_MyGamesAllScreen> {
  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFFE8002D);
  static const successGreen = Color(0xFF4ADE80);
  static const kText   = Color(0xFFF0F0F0);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);

  String _filter = 'all'; // 'all' | 'playing' | 'paused' | 'finished'

  void _showDeleteSheet() {
    final allList = widget.games
        .where((g) => g.rawgId != null)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final list = query.isEmpty
              ? allList
              : allList
                  .where((g) => g.name.toLowerCase().contains(query))
                  .toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: muted, borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Remove a game',
                          style: TextStyle(
                              color: kText, fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      autofocus: false,
                      style: const TextStyle(color: kText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search games...',
                        hintStyle: const TextStyle(color: muted, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: muted, size: 20),
                        suffixIcon: searchCtrl.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  searchCtrl.clear();
                                  setSheetState(() {});
                                },
                                child: const Icon(Icons.close, color: muted, size: 18),
                              )
                            : null,
                        filled: true,
                        fillColor: bg,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: border)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: accent, width: 1.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: border),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                    ),
                    child: list.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('No games found',
                                style: TextStyle(color: muted)),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final game = list[i];
                              return ListTile(
                                leading: game.displayImage != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.network(game.displayImage!,
                                            width: 36, height: 48, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                                Icons.sports_esports, color: muted, size: 28)),
                                      )
                                    : const Icon(Icons.sports_esports, color: muted, size: 28),
                                title: Text(game.name,
                                    style: const TextStyle(
                                        color: kText, fontSize: 14, fontWeight: FontWeight.w600),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: const Icon(Icons.delete_outline,
                                    color: accent, size: 20),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _confirmDelete(game);
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(LoggedGame game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove game?',
            style: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          'All logs for "${game.name}" will be permanently deleted.',
          style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: muted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<LoggedGamesProvider>().removeGame(game.rawgId!);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                // Green needs dark content text to stay readable.
                content: Text('"${game.name}" removed from your library',
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w600)),
                backgroundColor: successGreen,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 3),
              ));
            },
            child: const Text('Remove',
                style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, IconData icon, String label, Color color) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = active ? 'all' : value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color.withValues(alpha: 0.6) : border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? color : muted, size: 12),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: active ? color : muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayed = switch (_filter) {
      'playing'  => widget.games.where((g) => !g.isFinished && !g.isPaused).toList(),
      'paused'   => widget.games.where((g) => g.isPaused).toList(),
      'finished' => widget.games.where((g) => g.isFinished).toList(),
      _          => widget.games,
    };

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title,
            style: const TextStyle(
                color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: muted, size: 22),
            onPressed: widget.games.isEmpty ? null : _showDeleteSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: displayed.isEmpty
                ? Center(
                    child: Text(
                      switch (_filter) {
                        'playing'  => 'No games currently playing',
                        'paused'   => 'No paused games',
                        'finished' => 'No finished games',
                        _          => 'No games yet',
                      },
                      style: const TextStyle(color: muted, fontSize: 14),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.65,
                    ),
                    itemCount: displayed.length,
                    itemBuilder: (_, i) {
                      final g = displayed[i];
                      return GestureDetector(
                        onTap: () {
                          if (g.rawgId != null) {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => GameProfileScreen(
                                  rawgId: g.rawgId!, gameName: g.name),
                            ));
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                color: surface2,
                                child: g.displayImage != null
                                    ? Image.network(g.displayImage!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorBuilder: (_, __, ___) => Center(
                                            child: Text(g.name,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    color: kText,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700))))
                                    : Center(
                                        child: Text(g.name,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: kText,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700))),
                              ),
                              if (g.isPaused)
                                Positioned(
                                  bottom: 6, left: 0, right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFBBF24)
                                            .withValues(alpha: 0.88),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.pause,
                                              color: Colors.black, size: 9),
                                          SizedBox(width: 3),
                                          Text('Paused',
                                              style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (widget.showPausedFilter)
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: border)),
                color: bg,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    children: [
                      const Text('Filter',
                          style: TextStyle(
                              color: muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      _filterChip('playing',  Icons.sports_esports_outlined, 'Playing',  const Color(0xFF34D399)),
                      const SizedBox(width: 8),
                      _filterChip('paused',   Icons.pause,                   'Paused',   const Color(0xFFFBBF24)),
                      const SizedBox(width: 8),
                      _filterChip('finished', Icons.check_circle_outline,    'Finished', accent),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── All Games Screen ──────────────────────────────────────────────────────────
class _AllGamesScreen extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> games;
  final Map<String, Map<String, dynamic>> resolved;
  final void Function(String) onTap;
  const _AllGamesScreen({
    required this.title,
    required this.games,
    required this.resolved,
    required this.onTap,
  });

  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const kText = Color(0xFFF0F0F0);

  String? _imageUrl(String name) => resolved[name]?['imageUrl'] as String?;

  @override
  Widget build(BuildContext context) {
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
        title: Text(title,
            style: const TextStyle(
                color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.65,
        ),
        itemCount: games.length,
        itemBuilder: (_, i) {
          final g = games[i];
          final name = g['name'] as String? ?? '';
          final url = _imageUrl(name);
          final color = g['color'];
          final textColor = color is Color ? color : kText;
          return GestureDetector(
            onTap: () {
              Navigator.pop(context);
              onTap(name);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: url != null
                        ? CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorWidget: (_, __, ___) =>
                                _placeholder(g, textColor))
                        : _placeholder(g, textColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: kText,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.3)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder(Map<String, dynamic> g, Color textColor) {
    final title = g['title'] as String? ?? g['name'] as String? ?? '';
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surface2, surface],
        ),
      ),
      child: Center(
        child: Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: 0.3,
                height: 1.3)),
      ),
    );
  }
}

// ── Favorites All Screen ──────────────────────────────────────────────────────
class _FavoritesAllScreen extends StatelessWidget {
  final List<Map<String, dynamic>> favorites;
  const _FavoritesAllScreen({required this.favorites});

  static const bg      = Color(0xFF0E0E12);
  static const surface2= Color(0xFF1E1E2A);
  static const kText   = Color(0xFFF0F0F0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Favorite Games',
            style: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.65,
        ),
        itemCount: favorites.length,
        itemBuilder: (_, i) {
          final g = favorites[i];
          final name = g['name'] as String? ?? '';
          final imageUrl = (g['cover_image'] ?? g['background_image']) as String?;
          final rawgId = g['rawg_id'];
          return GestureDetector(
            onTap: () {
              if (rawgId != null) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => GameProfileScreen(
                    rawgId: rawgId is int ? rawgId : int.parse(rawgId.toString()),
                    gameName: name,
                  ),
                ));
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: surface2,
                child: imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: kText, fontSize: 10, fontWeight: FontWeight.w700)),
                        ))
                    : Center(
                        child: Text(name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: kText, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Nav Painters ──────────────────────────────────────────────────────────────
const _kText = Color(0xFFF0F0F0);
const _kMuted = Color(0xFF6B6B80);

Paint _navPaint(bool active) => Paint()
  ..color = active ? _kText : _kMuted
  ..strokeWidth = 2.0
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

class _HomePainter extends CustomPainter {
  final bool active;
  const _HomePainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.drawPath(
      Path()
        ..moveTo(3 * s, 9 * s)
        ..lineTo(12 * s, 2 * s)
        ..lineTo(21 * s, 9 * s)
        ..lineTo(21 * s, 20 * s)
        ..arcToPoint(Offset(19 * s, 22 * s), radius: Radius.circular(2 * s))
        ..lineTo(5 * s, 22 * s)
        ..arcToPoint(Offset(3 * s, 20 * s), radius: Radius.circular(2 * s))
        ..close(),
      _navPaint(active),
    );
  }

  @override
  bool shouldRepaint(_HomePainter o) => o.active != active;
}

class _SearchPainter extends CustomPainter {
  final bool active;
  const _SearchPainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    canvas.drawCircle(Offset(11 * s, 11 * s), 8 * s, p);
    canvas.drawLine(
        Offset(16.65 * s, 16.65 * s), Offset(21 * s, 21 * s), p);
  }

  @override
  bool shouldRepaint(_SearchPainter o) => o.active != active;
}

class _FriendsPainter extends CustomPainter {
  final bool active;
  const _FriendsPainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    canvas.drawPath(
      Path()
        ..moveTo(17 * s, 21 * s)
        ..lineTo(17 * s, 19 * s)
        ..arcToPoint(Offset(13 * s, 15 * s),
            radius: Radius.circular(4 * s), clockwise: false)
        ..lineTo(5 * s, 15 * s)
        ..arcToPoint(Offset(1 * s, 19 * s),
            radius: Radius.circular(4 * s), clockwise: false)
        ..lineTo(1 * s, 21 * s),
      p,
    );
    canvas.drawCircle(Offset(9 * s, 7 * s), 4 * s, p);
    canvas.drawPath(
      Path()
        ..moveTo(23 * s, 21 * s)
        ..lineTo(23 * s, 19 * s)
        ..arcToPoint(Offset(20 * s, 15.13 * s),
            radius: Radius.circular(4 * s), clockwise: false),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(16 * s, 3.13 * s)
        ..arcToPoint(Offset(16 * s, 10.88 * s),
            radius: Radius.circular(4 * s), clockwise: true),
      p,
    );
  }

  @override
  bool shouldRepaint(_FriendsPainter o) => o.active != active;
}

class _ProfilePainter extends CustomPainter {
  final bool active;
  const _ProfilePainter(this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    canvas.drawPath(
      Path()
        ..moveTo(20 * s, 21 * s)
        ..lineTo(20 * s, 19 * s)
        ..arcToPoint(Offset(16 * s, 15 * s),
            radius: Radius.circular(4 * s), clockwise: false)
        ..lineTo(8 * s, 15 * s)
        ..arcToPoint(Offset(4 * s, 19 * s),
            radius: Radius.circular(4 * s), clockwise: false)
        ..lineTo(4 * s, 21 * s),
      p,
    );
    canvas.drawCircle(Offset(12 * s, 7 * s), 4 * s, p);
  }

  @override
  bool shouldRepaint(_ProfilePainter o) => o.active != active;
}

class _PlusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, cy - 9), Offset(cx, cy + 9), p);
    canvas.drawLine(Offset(cx - 9, cy), Offset(cx + 9, cy), p);
  }

  @override
  bool shouldRepaint(_PlusPainter o) => false;
}

// ── Sticky Tab Bar Delegate ───────────────────────────────────────────────────
class _JournalAllScreen extends StatefulWidget {
  final List<LoggedGame> games;
  const _JournalAllScreen({required this.games});

  @override
  State<_JournalAllScreen> createState() => _JournalAllScreenState();
}

class _JournalAllScreenState extends State<_JournalAllScreen> {
  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFFE8002D);
  static const gold    = Color(0xFFF5C842);
  static const kText   = Color(0xFFF0F0F0);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);

  final _searchCtrl = TextEditingController();
  final Set<String> _expanded = {};
  bool _isSearching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();

    final Map<String, List<LoggedGame>> grouped = {};
    final List<String> order = [];
    for (final g in widget.games) {
      final key = g.rawgId?.toString() ?? g.name;
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        order.add(key);
      }
      grouped[key]!.add(g);
    }

    order.sort((a, b) {
      final aLatest = grouped[a]!
          .map((e) => e.loggedAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      final bLatest = grouped[b]!
          .map((e) => e.loggedAt)
          .reduce((x, y) => x.isAfter(y) ? x : y);
      return bLatest.compareTo(aLatest);
    });

    final filtered = query.isEmpty
        ? order
        : order.where((k) {
            final rep = grouped[k]!.first;
            return rep.name.toLowerCase().contains(query);
          }).toList();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kText, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: kText, fontSize: 15),
                cursorColor: accent,
                decoration: const InputDecoration(
                  hintText: 'Search journal...',
                  hintStyle: TextStyle(color: muted, fontSize: 15),
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Journal',
                style: TextStyle(
                    color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: !_isSearching,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search,
                color: kText, size: 22),
            onPressed: () => setState(() {
              if (_isSearching) {
                _searchCtrl.clear();
                _isSearching = false;
              } else {
                _isSearching = true;
              }
            }),
          ),
        ],
      ),
      body: filtered.isEmpty
          ? const Center(
              child: Text('No games found',
                  style: TextStyle(color: muted, fontSize: 14)),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final key = filtered[i];
                final entries = grouped[key]!;
                final rep = entries.reduce(
                    (a, b) => a.loggedAt.isAfter(b.loggedAt) ? a : b);
                final isExpanded = _expanded.contains(key);

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Column(children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          isExpanded ? _expanded.remove(key) : _expanded.add(key);
                        }),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 44, height: 58,
                                child: rep.displayImage != null
                                    ? Image.network(
                                        rep.displayImage!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _thumb(),
                                      )
                                    : _thumb(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(rep.name,
                                      style: const TextStyle(
                                          color: kText,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${entries.length} ${entries.length == 1 ? "entry" : "entries"}',
                                    style: const TextStyle(
                                        color: muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            AnimatedRotation(
                              turns: isExpanded ? 0.25 : 0,
                              duration: const Duration(milliseconds: 250),
                              child: Icon(Icons.chevron_right,
                                  color: isExpanded ? accent : muted),
                            ),
                          ]),
                        ),
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 250),
                        crossFadeState: isExpanded
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: const SizedBox.shrink(),
                        secondChild: Column(children: [
                          const Divider(color: border, height: 1),
                          ...entries.map((e) => _entry(e)),
                        ]),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }

  Widget _thumb() => Container(
        color: surface2,
        child: const Icon(Icons.sports_esports, color: muted, size: 20),
      );

  Widget _entry(LoggedGame entry) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    final d = entry.loggedAt;
    final dateStr = '${months[d.month - 1]} ${d.day}, ${d.year}';

    return GestureDetector(
      onTap: () {
        if (entry.rawgId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GameProfileScreen(
                  rawgId: entry.rawgId!, gameName: entry.name),
            ),
          );
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration:
            const BoxDecoration(border: Border(bottom: BorderSide(color: border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.calendar_today_outlined, color: muted, size: 12),
            const SizedBox(width: 4),
            Text(dateStr, style: const TextStyle(color: muted, fontSize: 11)),
            if (entry.hoursPlayed != null) ...[
              const SizedBox(width: 12),
              const Icon(Icons.access_time, color: muted, size: 12),
              const SizedBox(width: 4),
              Text(
                '${entry.hoursPlayed!.toStringAsFixed(entry.hoursPlayed! % 1 == 0 ? 0 : 1)} hrs',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ],
            if (entry.achievements.isNotEmpty) ...[
              const SizedBox(width: 12),
              const Icon(Icons.military_tech_outlined, color: muted, size: 12),
              const SizedBox(width: 4),
              Text('${entry.achievements.length}',
                  style: const TextStyle(color: muted, fontSize: 11)),
            ],
            if (entry.platform != null) ...[
              const SizedBox(width: 12),
              const Icon(Icons.videogame_asset_outlined, color: muted, size: 12),
              const SizedBox(width: 4),
              Text(entry.platform!,
                  style: const TextStyle(color: muted, fontSize: 11)),
            ],
          ]),
          if (entry.comment != null && entry.comment!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(entry.comment!,
                style: const TextStyle(
                    color: Color(0xCCF0F0F0), fontSize: 12, height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ],
          if (entry.achievements.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 4,
              children: entry.achievements.map((a) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: gold.withValues(alpha: 0.3)),
                  ),
                  child: Text(a,
                      style: const TextStyle(
                          color: gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                );
              }).toList(),
            ),
          ],
        ]),
      ),
    );
  }
}