import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFFE8002D);
  static const kText   = Color(0xFFF0F0F0);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);

  static const _faqs = [
    {
      'q': 'How do I add a game to my list?',
      'a': 'Search for a game, open its profile, then tap "Add to List". This feature is coming in GP2.',
    },
    {
      'q': 'How do I change my username?',
      'a': 'Go to your Profile and tap "Edit Profile" to update your username.',
    },
    {
      'q': 'Why are game images not loading?',
      'a': 'Make sure you have a stable internet connection. Game images are fetched from our servers.',
    },
    {
      'q': 'How do trophies work?',
      'a': 'Trophies are earned by completing games and achievements. Full trophy system coming in GP2.',
    },
    {
      'q': 'How do I follow other players?',
      'a': 'Friends & following features are coming in GP2.',
    },
  ];

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
        title: const Text('Help Center',
          style: TextStyle(color: kText, fontSize: 17,
              fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [

          // Header
          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A0A0A), Color(0xFF0A0A1A)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('👾', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 10),
                const Text('How can we help?',
                  style: TextStyle(color: kText, fontSize: 20,
                      fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Find answers or contact our team.',
                  style: TextStyle(color: muted, fontSize: 13)),
              ]),
          ),

          // FAQ section
          _sectionLabel('FREQUENTLY ASKED'),
          const SizedBox(height: 8),
          ..._faqs.map((f) => _FaqTile(
            question: f['q']!, answer: f['a']!)),
          const SizedBox(height: 24),

          // Contact section
          _sectionLabel('CONTACT US'),
          const SizedBox(height: 8),
          _contactCard(context),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 4, left: 2),
    child: Text(label, style: const TextStyle(
      color: muted, fontSize: 11, fontWeight: FontWeight.w700,
      letterSpacing: 1.2)),
  );

  Widget _contactCard(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withOpacity(0.3)),
          ),
          child: const Icon(Icons.mail_outline, color: accent, size: 20),
        ),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Email Support', style: TextStyle(color: kText, fontSize: 14,
              fontWeight: FontWeight.w700)),
          Text('We typically reply within 24h',
            style: TextStyle(color: muted, fontSize: 11)),
        ]),
      ]),
      const SizedBox(height: 14),
      const Divider(color: border, height: 1),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: () async {
          final uri = Uri(
            scheme: 'mailto',
            path: 'loadoutprojectteam@gmail.com',
          );
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: const Text('loadoutprojectteam@gmail.com',
          style: TextStyle(color: accent, fontSize: 14,
              fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 6),
      const Text('For bug reports, feedback, or account issues.',
        style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
    ]),
  );
}

class _FaqTile extends StatefulWidget {
  final String question, answer;
  const _FaqTile({required this.question, required this.answer});
  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  static const surface = Color(0xFF16161E);
  static const kText   = Color(0xFFF0F0F0);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);
  static const accent  = Color(0xFFE8002D);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(child: Text(widget.question,
                style: const TextStyle(color: kText, fontSize: 14,
                    fontWeight: FontWeight.w600))),
              AnimatedRotation(
                turns: _open ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.chevron_right,
                  color: _open ? accent : muted, size: 20),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _open
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(widget.answer,
              style: const TextStyle(color: muted, fontSize: 13,
                  height: 1.6)),
          ),
        ),
      ]),
    );
  }
}
