// Fetches the user's Wrapped and opens it, or explains why it can't: still
// locked until its release date, or a load error with a retry.

import 'package:flutter/material.dart';

import '../../models/wrapped.dart';
import '../../services/wrapped_service.dart';
import 'wrapped_card.dart';
import 'wrapped_screen.dart';

class WrappedEntryScreen extends StatefulWidget {
  final int? year;

  const WrappedEntryScreen({super.key, this.year});

  @override
  State<WrappedEntryScreen> createState() => _WrappedEntryScreenState();
}

class _WrappedEntryScreenState extends State<WrappedEntryScreen> {
  late Future<Map<String, dynamic>> _load = WrappedService().getWrapped(year: widget.year);

  void _retry() => setState(() => _load = WrappedService().getWrapped(year: widget.year));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _load,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) {
          return Scaffold(
            body: WrappedBackdrop(
              palette: WrappedPalette.hours,
              drift: kAlwaysDismissedAnimation,
              child: Center(child: CircularProgressIndicator(color: WrappedPalette.hours.accentColor)),
            ),
          );
        }
        if (result['success'] != true) {
          return _Message(
            title: "Couldn't load your ${widget.year ?? DateTime.now().year} Endgame",
            body: result['message'] as String? ?? '',
            action: FilledButton(
              onPressed: _retry,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              child: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          );
        }
        final wrapped = result['wrapped'] as WrappedResponse;
        if (wrapped.locked) {
          final release = wrapped.releaseDate;
          return _Message(
            title: 'Your ${wrapped.year} Endgame is on its way',
            body: release == null
                ? 'Check back at the end of the year.'
                : 'It unlocks on ${wrappedMonths[release.month - 1]} ${release.day}.',
          );
        }
        return WrappedScreen(data: wrapped);
      },
    );
  }
}

class _Message extends StatelessWidget {
  final String title;
  final String body;
  final Widget? action;

  const _Message({required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    const palette = WrappedPalette.hours;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: WrappedBackdrop(
        palette: palette,
        drift: kAlwaysDismissedAnimation,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WrappedEyebrow('Endgame', color: palette.accentColor, icon: Icons.auto_awesome_rounded),
                const SizedBox(height: 16),
                Text(title, textAlign: TextAlign.center, style: WrappedText.headline(context).copyWith(fontSize: 32)),
                const SizedBox(height: 12),
                Text(body, textAlign: TextAlign.center, style: WrappedText.medium(context).copyWith(fontSize: 17)),
                if (action != null) ...[const SizedBox(height: 28), action!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
