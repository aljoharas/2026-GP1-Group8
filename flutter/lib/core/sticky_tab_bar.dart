import 'package:flutter/material.dart';

/// Pins a [TabBar] under a scrolling profile header.
///
/// Shared by your own profile and another user's, so the two screens pin their
/// tabs at the same height and against the same background — the tab strip is
/// the most visible seam between them, and a private copy per screen is how
/// they drift apart.
class StickyTabBar extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const StickyTabBar(this.tabBar);

  static const bg = Color(0xFF0E0E12);
  static const border = Color(0x12FFFFFF);

  // The extra pixel is the divider below the strip.
  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: bg,
      child: Column(
        children: [
          tabBar,
          const Divider(height: 1, color: border),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(StickyTabBar old) => old.tabBar != tabBar;
}
