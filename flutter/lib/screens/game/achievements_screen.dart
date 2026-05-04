import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class AchievementsScreen extends StatelessWidget {
  final String gameName;
  final List<dynamic> achievements;

  const AchievementsScreen({
    super.key,
    required this.gameName,
    required this.achievements,
  });

  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161E);
  static const surface2 = Color(0xFF1E1E2A);
  static const muted = Color(0xFF6B6B80);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        title: Text(
          '$gameName — Trophies',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: achievements.length,
        itemBuilder: (context, index) => _buildRow(achievements[index]),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> a) {
    final percent = double.tryParse(a['percent']?.toString() ?? '') ?? 100.0;
    final Color badgeColor;
    final String rarity;
    if (percent < 10) {
      badgeColor = const Color(0xFFFBBF24);
      rarity = 'Gold';
    } else if (percent < 30) {
      badgeColor = const Color(0xFF94A3B8);
      rarity = 'Silver';
    } else {
      badgeColor = const Color(0xFFB4783C);
      rarity = 'Bronze';
    }

    final imageUrl = a['image'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _iconFallback(),
                  )
                : _iconFallback(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a['name'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((a['description'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    a['description'],
                    style: const TextStyle(color: muted, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  rarity,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconFallback() => Container(
        width: 48,
        height: 48,
        color: surface2,
        child: const Center(child: Text('🏆', style: TextStyle(fontSize: 22))),
      );
}
