// Shared building blocks for the Gaming Wrapped cards: when a card animates,
// its colours and backdrop, how it shows images, its text styles, and how it
// formats hours.

import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

const wrappedPlaceholderColor = Color(0xFF1A1A22);

/// A Wrapped page. The screen precaches its [imageUrls] one page ahead.
abstract interface class WrappedCard {
  List<String> get imageUrls;
}

/// Tells a card whether it is the page the user has settled on.
class WrappedPageScope extends InheritedWidget {
  final bool active;

  const WrappedPageScope({super.key, required this.active, required super.child});

  /// True outside a Wrapped PageView, so a card shown on its own still plays.
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WrappedPageScope>()?.active ?? true;

  @override
  bool updateShouldNotify(WrappedPageScope oldWidget) => active != oldWidget.active;
}

/// Base state for a card: one [entrance] controller that plays from the start
/// each time the card becomes the visible page, plus optional [loops] that
/// repeat while it stays visible. Leaving the page rewinds both. With reduced
/// motion the card shows its final frame and the loops stay still.
abstract class WrappedCardState<T extends StatefulWidget> extends State<T> with TickerProviderStateMixin {
  late final AnimationController entrance = AnimationController(vsync: this, duration: entranceDuration);

  Duration get entranceDuration;

  /// Continuous animations (drift, float, Ken Burns), each run with repeat().
  /// Subclasses create them; this class starts, stops and disposes them.
  List<AnimationController> get loops => const [];

  /// Slow loop that drifts the backdrop glows. Runs like the other loops.
  late final AnimationController ambient = AnimationController(vsync: this, duration: const Duration(seconds: 18));

  List<AnimationController> get _allLoops => [ambient, ...loops];

  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = WrappedPageScope.isActive(context);
    if (!active) {
      if (_active) _rewind();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _rewind();
      entrance.value = 1;
    } else if (!_active) {
      entrance.forward(from: 0);
      for (final loop in _allLoops) {
        loop.repeat();
      }
    }
    _active = active;
  }

  void _rewind() {
    entrance.reset();
    for (final loop in _allLoops) {
      loop.reset();
    }
  }

  @override
  void dispose() {
    entrance.dispose();
    for (final loop in _allLoops) {
      loop.dispose();
    }
    super.dispose();
  }
}

/// The slice of [total] that starts at [startMs] and lasts [lengthMs].
Curve msInterval(int startMs, int lengthMs, Duration total, {Curve curve = Curves.linear}) {
  final totalMs = total.inMilliseconds;
  return Interval((startMs / totalMs).clamp(0.0, 1.0), ((startMs + lengthMs) / totalMs).clamp(0.0, 1.0), curve: curve);
}

/// Fades [child] in while sliding it up by [distance] as [t] goes 0 → 1.
Widget riseIn(double t, Widget child, {double distance = 24}) => Opacity(
  opacity: t.clamp(0.0, 1.0),
  child: Transform.translate(offset: Offset(0, distance * (1 - t)), child: child),
);

// --- Images ------------------------------------------------------------------

/// A network image that fills its box, with a dark placeholder while loading
/// and on error (never a broken-image icon).
class WrappedImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;

  const WrappedImage(this.url, {super.key, this.fit = BoxFit.cover});

  static const _placeholder = ColoredBox(color: wrappedPlaceholderColor);

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return SizedBox.expand(
      child: url == null
          ? _placeholder
          : CachedNetworkImage(
              imageUrl: url,
              fit: fit,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (_, _) => _placeholder,
              errorWidget: (_, _, _) => _placeholder,
            ),
    );
  }
}

/// Loads [url] into the image cache so [WrappedImage] can show it at once.
/// Uses the same provider CachedNetworkImage builds, so the cache key matches.
Future<void> precacheWrappedImage(String url, BuildContext context) =>
    precacheImage(CachedNetworkImageProvider(url), context, onError: (_, _) {});

// --- Palettes & backdrop -----------------------------------------------------

/// A card's colours: a deep [base], three [glows] that drift behind the
/// content, and the two-stop [accent] gradient for its headline numbers.
class WrappedPalette {
  final Color base;
  final List<Color> glows;
  final List<Color> accent;

  const WrappedPalette({required this.base, required this.glows, required this.accent});

  Color get accentColor => accent.first;

  static const hours = WrappedPalette(
    base: Color(0xFF0A0718),
    glows: [Color(0xFF6D28D9), Color(0xFF1D4ED8), Color(0xFF15803D)],
    accent: [Color(0xFF4ADE80), Color(0xFF22D3EE)],
  );
  static const gamesPlayed = WrappedPalette(
    base: Color(0xFF06061A),
    glows: [Color(0xFF4338CA), Color(0xFF1D4ED8), Color(0xFF6D28D9)],
    accent: [Color(0xFFA5B4FC), Color(0xFF818CF8)],
  );
  static const topGame = WrappedPalette(
    base: Color(0xFF0C0805),
    glows: [Color(0xFFB45309), Color(0xFF9D174D), Color(0xFF78350F)],
    accent: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
  );
  static const topGames = WrappedPalette(
    base: Color(0xFF16040A),
    glows: [Color(0xFFBE123C), Color(0xFF9F1239), Color(0xFF7C3AED)],
    accent: [Color(0xFFFDA4AF), Color(0xFFFB7185)],
  );
  static const topOnline = WrappedPalette(
    base: Color(0xFF040A16),
    glows: [Color(0xFF0E7490), Color(0xFF4F46E5), Color(0xFF0891B2)],
    accent: [Color(0xFF67E8F9), Color(0xFF818CF8)],
  );
  static const trophies = WrappedPalette(
    base: Color(0xFF050A12),
    glows: [Color(0xFF1E3A5F), Color(0xFF334155), Color(0xFF0C4A6E)],
    accent: [Color(0xFFB9D7EA), Color(0xFFE0F2FE)],
  );
  static const playerType = WrappedPalette(
    base: Color(0xFF0B0616),
    glows: [Color(0xFF6D28D9), Color(0xFF9D174D), Color(0xFF4338CA)],
    accent: [Color(0xFFC4B5FD), Color(0xFFF0ABFC)],
  );
  static const gameStatus = WrappedPalette(
    base: Color(0xFF050F0A),
    glows: [Color(0xFF166534), Color(0xFF0F766E), Color(0xFF3F6212)],
    accent: [Color(0xFFBEF264), Color(0xFF4ADE80)],
  );
  static const rating = WrappedPalette(
    base: Color(0xFF110B03),
    glows: [Color(0xFFB45309), Color(0xFF7C2D12), Color(0xFF4338CA)],
    accent: [Color(0xFFFCD34D), Color(0xFFF59E0B)],
  );
  static const friendsHours = WrappedPalette(
    base: Color(0xFF130805),
    glows: [Color(0xFFC2410C), Color(0xFF9F1239), Color(0xFF78350F)],
    accent: [Color(0xFFFB923C), Color(0xFFFDBA74)],
  );
  static const gamingTwin = WrappedPalette(
    base: Color(0xFF10050E),
    glows: [Color(0xFFBE185D), Color(0xFF6D28D9), Color(0xFF9D174D)],
    accent: [Color(0xFFF9A8D4), Color(0xFFF0ABFC)],
  );
}

/// The layered background every card sits on: base colour, an optional
/// [behind] layer (e.g. game art), drifting glows, film grain and a vignette.
class WrappedBackdrop extends StatelessWidget {
  final WrappedPalette palette;
  final Animation<double> drift;
  final Widget? behind;
  final double glowOpacity;
  final Widget child;

  const WrappedBackdrop({
    super.key,
    required this.palette,
    required this.drift,
    this.behind,
    this.glowOpacity = 1,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: palette.base),
        ?behind,
        RepaintBoundary(child: CustomPaint(painter: _GlowPainter(palette.glows, drift, glowOpacity))),
        const RepaintBoundary(child: CustomPaint(painter: _GrainPainter())),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(radius: 1.1, colors: [Color(0x00000000), Color(0x8C000000)], stops: [0.55, 1.0]),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowPainter extends CustomPainter {
  final List<Color> colors;
  final Animation<double> drift;
  final double opacity;

  _GlowPainter(this.colors, this.drift, this.opacity) : super(repaint: drift);

  static const _anchors = [Offset(0.1, 0.12), Offset(0.95, 0.5), Offset(0.25, 0.92)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = drift.value;
    final radius = size.longestSide * 0.55;
    for (var i = 0; i < colors.length && i < _anchors.length; i++) {
      final phase = 2 * pi * (t + i / 3);
      final centre = Offset(
        size.width * (_anchors[i].dx + 0.1 * sin(phase)),
        size.height * (_anchors[i].dy + 0.06 * cos(phase)),
      );
      final rect = Rect.fromCircle(center: centre, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            colors[i].withValues(alpha: 0.6 * opacity),
            colors[i].withValues(alpha: 0),
          ],
        ).createShader(rect);
      canvas.drawCircle(centre, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.colors != colors || old.drift != drift || old.opacity != opacity;
}

/// Fine static noise, so the gradients read as print rather than flat fills.
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7);
    final count = (size.width * size.height / 70).round();
    final light = <Offset>[];
    final dark = <Offset>[];
    for (var i = 0; i < count; i++) {
      final point = Offset(random.nextDouble() * size.width, random.nextDouble() * size.height);
      (i.isEven ? light : dark).add(point);
    }
    final paint = Paint()..strokeWidth = 1;
    canvas.drawPoints(PointMode.points, light, paint..color = const Color(0x0DFFFFFF));
    canvas.drawPoints(PointMode.points, dark, paint..color = const Color(0x14000000));
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

/// Slowly zooms and pans [child] with [controller] (a repeating loop): 8 s
/// in, 8 s back out, eased at both ends so the loop never jumps.
class WrappedKenBurns extends StatelessWidget {
  final Animation<double> controller;
  final Widget child;

  const WrappedKenBurns({super.key, required this.controller, required this.child});

  static const period = Duration(seconds: 16);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final k = 0.5 - 0.5 * cos(2 * pi * controller.value);
        // The pan stays within the margin the zoom adds, so no edge shows.
        return Transform.translate(
          offset: Offset(-0.03 * size.width * k, -0.02 * size.height * k),
          child: Transform.scale(scale: 1.15 + 0.12 * k, child: child),
        );
      },
      child: child,
    );
  }
}

// --- Split layout --------------------------------------------------------------

/// Space under the status bar kept for the progress bar and close button.
const kWrappedChromeHeight = 64.0;

/// Space kept clear at the bottom of every card.
const kWrappedBottomClearance = 36.0;

/// The skeleton of cards 6–11: a [visual] zone at the top and a left-aligned
/// [text] zone anchored to the bottom. The visual takes the space the text
/// leaves, up to [visualFraction] of the screen, and is centred in any extra.
///
/// With [expandText] the visual keeps exactly its share and the text zone
/// takes the rest, for text zones that scroll.
class WrappedSplitLayout extends StatelessWidget {
  final Widget visual;
  final Widget text;
  final double visualFraction;
  final bool expandText;

  const WrappedSplitLayout({
    super.key,
    required this.visual,
    required this.text,
    this.visualFraction = 0.6,
    this.expandText = false,
  });

  static const _gap = 28.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size.height;
    final top = media.padding.top + kWrappedChromeHeight;
    final bottom = media.padding.bottom + kWrappedBottomClearance;
    final visualHeight = max(0.0, screen * visualFraction - top);
    final textZone = Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: text);

    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: expandText
            ? [SizedBox(height: visualHeight, child: visual), const SizedBox(height: 20), Expanded(child: textZone)]
            : [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: SizedBox(height: min(constraints.maxHeight, visualHeight), child: visual),
                    ),
                  ),
                ),
                const SizedBox(height: _gap),
                textZone,
              ],
      ),
    );
  }
}

/// A soft radial light behind a card's hero visual.
class WrappedHeroGlow extends StatelessWidget {
  final Color color;
  final double strength;

  const WrappedHeroGlow({super.key, required this.color, this.strength = 0.3});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        // Fades out within half the shorter side, so the box never shows.
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.5,
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: strength * 0.35),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// A caps headline that never breaks inside a word: on one line it scales
/// down to fit; with [maxLines] above 1 it may break between words, and
/// shrinks only as far as the longest word and the line count need, but
/// not below [minFontSize] (then it ellipsizes).
class WrappedHeadline extends StatelessWidget {
  final String text;
  final int maxLines;
  final double minFontSize;

  const WrappedHeadline(this.text, {super.key, this.maxLines = 1, this.minFontSize = 12});

  @override
  Widget build(BuildContext context) {
    final style = WrappedText.display(context);
    if (maxLines == 1) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, style: style),
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var widest = 0.0;
        for (final word in text.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: style),
            textScaler: scaler,
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          widest = max(widest, painter.width);
          painter.dispose();
        }
        var size = max(minFontSize, style.fontSize! * min(1.0, constraints.maxWidth / widest) * 0.98);
        // Then smaller still, until the whole headline fits in maxLines.
        while (size > minFontSize) {
          final painter = TextPainter(
            text: TextSpan(
              text: text,
              style: style.copyWith(fontSize: size),
            ),
            textScaler: scaler,
            textDirection: TextDirection.ltr,
            maxLines: maxLines,
          )..layout(maxWidth: constraints.maxWidth);
          final fits = !painter.didExceedMaxLines;
          painter.dispose();
          if (fits) break;
          size = max(minFontSize, size * 0.95);
        }
        return Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: size),
        );
      },
    );
  }
}

/// The supporting line under a headline, kept to two lines: at large text
/// sizes it shrinks (no smaller than its unscaled size) rather than cut
/// words off. A "★" draws as a star icon, which every font can show.
class WrappedSupportingLine extends StatelessWidget {
  final String text;

  const WrappedSupportingLine(this.text, {super.key});

  static const _maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final style = WrappedText.supporting(context);
    final base = style.fontSize!;
    final scale = MediaQuery.textScalerOf(context).scale(base) / base;
    return LayoutBuilder(
      builder: (context, constraints) {
        var size = base * scale;
        while (size > base && !_fits(style.copyWith(fontSize: size), constraints.maxWidth)) {
          size = max(base, size - 0.5);
        }
        final sized = style.copyWith(fontSize: size);
        return Text.rich(
          _spans(sized),
          maxLines: _maxLines + (_fits(sized, constraints.maxWidth) ? 0 : 1),
          overflow: TextOverflow.ellipsis,
          textScaler: TextScaler.noScaling,
          style: sized,
        );
      },
    );
  }

  bool _fits(TextStyle style, double width) {
    // "M" stands in for the star icon; both are about a font size wide.
    final painter = TextPainter(
      text: TextSpan(text: text.replaceAll('★', 'M'), style: style),
      maxLines: _maxLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
  }

  TextSpan _spans(TextStyle style) {
    final parts = text.split('★');
    return TextSpan(
      children: [
        for (final (i, part) in parts.indexed) ...[
          if (i > 0)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.star_rounded, size: style.fontSize! * 1.05, color: style.color),
            ),
          TextSpan(text: part),
        ],
      ],
    );
  }
}

/// One label/value column of a [WrappedStatPairs] row.
class WrappedStat {
  final IconData icon;
  final String label;
  final String value;

  const WrappedStat({required this.icon, required this.label, required this.value});
}

/// Two stats side by side: a small caps label with an icon over a big value.
class WrappedStatPairs extends StatelessWidget {
  final List<WrappedStat> stats;
  final Color accent;

  const WrappedStatPairs({super.key, required this.stats, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelMedium!.copyWith(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
    );
    final value = theme.textTheme.headlineMedium!.copyWith(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, stat) in stats.indexed) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(stat.icon, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Text(stat.label, style: label),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(stat.value, maxLines: 1, style: value),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A round avatar, or the person's initials when there's no picture.
class WrappedAvatar extends StatelessWidget {
  final String? url;
  final String? name;
  final double size;
  final Color tint;

  const WrappedAvatar({super.key, required this.url, required this.name, required this.size, required this.tint});

  static String initials(String? name) {
    final words = (name ?? '').trim().split(RegExp(r'[\s_.-]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(tint, Colors.black, 0.45)!, Color.lerp(tint, Colors.black, 0.75)!],
        ),
      ),
      child: Center(
        child: Text(
          initials(name),
          textScaler: TextScaler.noScaling,
          style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w800),
        ),
      ),
    );
    final url = this.url;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? fallback
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

// --- Text --------------------------------------------------------------------

abstract final class WrappedText {
  static TextStyle medium(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleLarge!.copyWith(
      color: Colors.white.withValues(alpha: 0.85),
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.3,
      letterSpacing: -0.2,
    );
  }

  /// A big bold title, e.g. a game's name.
  static TextStyle headline(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.displaySmall!.copyWith(
      color: Colors.white,
      fontSize: 38,
      fontWeight: FontWeight.w900,
      height: 1.05,
      letterSpacing: -1.2,
    );
  }

  /// The caps headline in a card's text zone. Keep it on one line in a
  /// scale-down FittedBox.
  static TextStyle display(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.displayMedium!.copyWith(
      color: Colors.white,
      fontSize: 52,
      fontWeight: FontWeight.w900,
      height: 0.95,
      letterSpacing: -1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// The line under a headline.
  static TextStyle supporting(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodyLarge!.copyWith(
      color: Colors.white.withValues(alpha: 0.72),
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );
  }

  /// The very large number on a stat card. Wrap it in a scale-down FittedBox
  /// and a [WrappedGradientText] for colour.
  static TextStyle huge(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.displayLarge!.copyWith(
      color: Colors.white,
      fontSize: 136,
      fontWeight: FontWeight.w900,
      height: 1.0,
      letterSpacing: -5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
}

/// [text] filled with a diagonal gradient of [colors].
class WrappedGradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final List<Color> colors;
  final TextAlign? textAlign;

  const WrappedGradientText(this.text, {super.key, required this.style, required this.colors, this.textAlign});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors).createShader(bounds),
      child: Text(text, style: style, textAlign: textAlign),
    );
  }
}

/// Small spaced-out caps label above a card's main content.
class WrappedEyebrow extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final double? fontSize;
  final double letterSpacing;

  const WrappedEyebrow(this.text, {super.key, required this.color, this.icon, this.fontSize, this.letterSpacing = 2.6});

  /// The smaller eyebrow of a [WrappedTextZone].
  const WrappedEyebrow.zone(this.text, {super.key, required this.color, this.icon})
    : fontSize = 13,
      letterSpacing = 1.2;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!.copyWith(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: (fontSize ?? 14) + 2, color: color), const SizedBox(width: 8)],
          Text(text.toUpperCase(), style: style),
        ],
      ),
    );
  }
}

/// A frosted-glass capsule for a supporting stat.
class WrappedPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? iconColor;

  const WrappedPill(this.text, {super.key, this.icon, this.iconColor});

  static final _radius = BorderRadius.circular(999);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.titleSmall!.copyWith(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.1);
    return ClipRRect(
      borderRadius: _radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: _radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: iconColor ?? Colors.white), const SizedBox(width: 8)],
                Flexible(
                  child: Text(text, style: style, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Formatting --------------------------------------------------------------

/// [value] with [decimals] decimal places and thousands separators.
String formatNumber(double value, {int decimals = 0}) {
  final parts = value.toStringAsFixed(decimals).split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return parts.length == 1 ? whole : '$whole.${parts[1]}';
}

double _toTenths(double hours) => (hours * 10).round() / 10;

/// Decimal places hours are shown with: none when whole, otherwise one.
int hoursDecimals(double hours) {
  final tenths = _toTenths(hours);
  return tenths == tenths.roundToDouble() ? 0 : 1;
}

/// "96", "41.5", "1,204".
String formatHoursValue(double hours) => formatNumber(_toTenths(hours), decimals: hoursDecimals(hours));

String hoursUnit(double hours) => _toTenths(hours) == 1 ? 'hour' : 'hours';

/// "96 hours", "41.5 hours", "1 hour".
String formatHours(double hours) => '${formatHoursValue(hours)} ${hoursUnit(hours)}';

const wrappedMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2 May".
String formatDayMonth(DateTime date) => '${date.day} ${wrappedMonths[date.month - 1]}';
