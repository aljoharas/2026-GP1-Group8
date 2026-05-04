import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/logged_games_provider.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _reminders = false;

  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFFE8002D);
  static const kText   = Color(0xFFF0F0F0);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);

  @override
  Widget build(BuildContext context) {
    final auth     = context.watch<AuthProvider>();
    final user     = auth.currentUser;
    final username = user?['username'] as String? ?? '—';
    final email    = user?['email']    as String? ?? '—';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings',
          style: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [

          // ── ACCOUNT ──────────────────────────────────────────────────────
          _sectionLabel('ACCOUNT'),
          _card([
            _infoRow('Username', username),
            _divider(),
            _infoRow('Email', email),
          ]),

          const SizedBox(height: 24),

          // ── PREFERENCES ──────────────────────────────────────────────────
          _sectionLabel('PREFERENCES'),
          _card([
            _toggleRow(
              icon: Icons.notifications_outlined,
              label: 'Game Reminders',
              sub: 'Coming in GP2',
              value: _reminders,
              onChanged: (_) => _sprint2(),
            ),
          ]),

          const SizedBox(height: 32),

          // ── LOG OUT ──────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _confirmLogout(context, auth),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Log Out',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Logout confirm dialog ─────────────────────────────────────────────────
  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16161E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out?',
          style: TextStyle(color: Color(0xFF6B6B80))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF6B6B80))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              context.read<LoggedGamesProvider>().reset();
              await auth.logout();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Log Out',
              style: TextStyle(color: Color(0xFFE8002D),
                  fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _sprint2([String label = 'This feature']) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16161E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF6B6B80).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2))),
          const Text('🚧', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 12),
          Text('$label coming in GP2!',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('This feature is on its way.',
            style: TextStyle(color: Color(0xFF6B6B80), fontSize: 13)),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(label, style: const TextStyle(
      color: muted, fontSize: 11, fontWeight: FontWeight.w700,
      letterSpacing: 1.2)),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border),
    ),
    child: Column(children: children),
  );

  Widget _divider() => const Divider(color: border, height: 1, indent: 16, endIndent: 16);

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 14)),
      Text(value, style: const TextStyle(color: kText, fontSize: 14,
          fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _toggleRow({required IconData icon, required String label,
      required String sub, required bool value,
      required ValueChanged<bool> onChanged}) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, color: muted, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: kText, fontSize: 14)),
            Text(sub, style: const TextStyle(color: muted, fontSize: 11)),
          ])),
        Switch(value: value, onChanged: onChanged,
          activeColor: accent,
          inactiveTrackColor: surface2),
      ]),
    );
}
