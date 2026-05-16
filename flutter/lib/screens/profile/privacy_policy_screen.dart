import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const bg      = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2= Color(0xFF1E1E2A);
  static const accent  = Color(0xFF4ADE80);
  static const muted   = Color(0xFF6B6B80);
  static const border  = Color(0x12FFFFFF);
  static const kText   = Color(0xFFF0F0F0);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: const Text(
            'Privacy & Legal',
            style: TextStyle(
                color: kText, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          bottom: TabBar(
            labelColor: accent,
            unselectedLabelColor: muted,
            indicatorColor: accent,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Privacy Policy'),
              Tab(text: 'Terms of Use'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PolicyTab(content: _privacyContent),
            _PolicyTab(content: _termsContent),
          ],
        ),
      ),
    );
  }
}

// ── Tab content ────────────────────────────────────────────────────────────────
class _PolicyTab extends StatelessWidget {
  final List<_PolicySection> content;
  const _PolicyTab({required this.content});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        for (final section in content) ...[
          _SectionWidget(section: section),
          const SizedBox(height: 20),
        ],
        const Center(
          child: Text(
            'loadout · Graduation Project 2026',
            style: TextStyle(
                color: PrivacyPolicyScreen.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _SectionWidget extends StatelessWidget {
  final _PolicySection section;
  const _SectionWidget({required this.section});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PrivacyPolicyScreen.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PrivacyPolicyScreen.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              color: PrivacyPolicyScreen.kText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: const TextStyle(
              color: PrivacyPolicyScreen.muted,
              fontSize: 13,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data ───────────────────────────────────────────────────────────────────────
class _PolicySection {
  final String title;
  final String body;
  const _PolicySection(this.title, this.body);
}

const _privacyContent = [
  _PolicySection(
    'What We Collect',
    '• Username and email when you register.\n'
    '• Optional bio and profile picture.\n'
    '• Games you log, hours played, and comments.',
  ),
  _PolicySection(
    'How We Use It',
    'Your data is used only to run your account and show your activity to '
    'friends. We do not sell or share your personal data with third parties.',
  ),
  _PolicySection(
    'Storage & Security',
    'Data is stored securely via Firebase. Passwords are never stored — '
    'login is handled entirely by Firebase Authentication.',
  ),
  _PolicySection(
    'Third-Party Services',
    'Game info is fetched from the RAWG API and is publicly available. '
    'Firebase is governed by Google\'s Privacy Policy.',
  ),
  _PolicySection(
    'Your Rights',
    'You can update your profile anytime.',
  ),
];

const _termsContent = [
  _PolicySection(
    'Agreement',
    'By creating an account you agree to these terms. If you do not agree, '
    'please do not use the app.',
  ),
  _PolicySection(
    'Eligibility',
    'loadout is for users aged 13 and older.',
  ),
  _PolicySection(
    'Your Account',
    '• Keep your credentials secure.\n'
    '• Provide accurate information.\n'
    '• Do not impersonate others.',
  ),
  _PolicySection(
    'Acceptable Use',
    'Do not post harmful content, access other accounts without permission, '
    'or use the app for any unlawful purpose.',
  ),
  _PolicySection(
    'Disclaimer',
    'loadout is a graduation project provided "as is". We are not liable '
    'for data loss or service interruptions.',
  ),
];
