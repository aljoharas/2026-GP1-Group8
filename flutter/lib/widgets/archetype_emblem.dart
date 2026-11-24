import 'package:flutter/material.dart';

// Player Archetype emblems (Style B): a hexagon filled with the archetype's
// family colour, with a white line icon inside. Drawn from the 24×24 SVG design
// with a CustomPainter, so no SVG package is needed.

const kLightFamily = Color(0xFF1FA99D);
const kCommittedFamily = Color(0xFF7C6CF2);
const kOneGameFamily = Color(0xFFD98A16);

const Map<String, String> archetypeFamily = {
  'Casual': 'Light',
  'Explorer': 'Light',
  'Competitor': 'Committed',
  'Completionist': 'Committed',
  'Devotee': 'One-game',
  'The Main': 'One-game',
};

const Map<String, Color> _familyColour = {
  'Light': kLightFamily,
  'Committed': kCommittedFamily,
  'One-game': kOneGameFamily,
};

/// The family colour for an archetype (or a neutral grey for an unknown name)
Color archetypeColour(String? archetype) =>
    _familyColour[archetypeFamily[archetype]] ?? const Color(0xFF6B6B80);

/// "Light player", "Committed player", "One-game player"; null when unknown
String? familyLabel(String? family) => family == null ? null : '$family player';

const _hexagon = 'M12 1.4l9.2 5.3v10.6L12 22.6l-9.2-5.3V6.7z';

/// The six icon paths, in the 24×24 icon space (drawn at translate(4.8, 4.8) scale(0.6))
const Map<String, String> archetypeIconPaths = {
  'Completionist': 'M8 4h8v4a4 4 0 0 1-8 0zM8 5H5.5a2 2 0 0 0 2.5 3.5M16 5h2.5a2 2 0 0 1-2.5 3.5M12 12v3M9 19h6M10 15h4v4h-4z',
  'Explorer': 'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0M16 8l-2 6-6 2 2-6z',
  'Competitor': 'M5 5l10 10M19 5L9 15M13 17l4-4M7 13l4 4M16.5 16.5L19 19M7.5 16.5L5 19',
  'Devotee':
      'M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21l7.8-7.5 1-1.1a5.5 5.5 0 0 0 0-7.8z',
  'The Main': 'M4 18h16M5 15.5L4 6l5 4 3-6 3 6 5-4-1 9.5z',
  'Casual': 'M5 10h10v5a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4zM15 11.5h1.5a2.2 2.2 0 0 1 0 4.4H15M8.5 7c0-1 1-1 1-2M11.5 7c0-1 1-1 1-2',
};

/// One archetype's emblem. [size] is the square edge in logical pixels (22 in
/// the badge, 56 in the details sheet). [faded] draws it at 45% opacity.
class ArchetypeEmblem extends StatelessWidget {
  final String archetype;
  final double size;
  final bool faded;
  final double opacity;

  const ArchetypeEmblem({super.key, required this.archetype, this.size = 22, this.faded = false, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    final alpha = (faded ? 0.45 : 1.0) * opacity;
    final emblem = CustomPaint(
      size: Size.square(size),
      painter: _EmblemPainter(archetype),
    );
    return ExcludeSemantics(
      child: SizedBox.square(dimension: size, child: alpha >= 1 ? emblem : Opacity(opacity: alpha, child: emblem)),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  final String archetype;
  _EmblemPainter(this.archetype);

  static final Path _hex = parseSvgPath(_hexagon);
  static final Map<String, Path> _iconPaths = {for (final e in archetypeIconPaths.entries) e.key: parseSvgPath(e.value)};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(_hex, Paint()..color = archetypeColour(archetype));
    canvas.drawPath(
      _hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.22),
    );
    final icon = _iconPaths[archetype];
    if (icon != null) {
      // The icon sits inside the hexagon: translate(4.8, 4.8) scale(0.6); the
      // stroke width is in icon units, so it scales with the icon as in SVG
      canvas.translate(4.8, 4.8);
      canvas.scale(0.6);
      canvas.drawPath(
        icon,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EmblemPainter old) => old.archetype != archetype;
}

/// A minimal SVG path parser for the commands the emblem paths use: M L H V C A Z
/// (absolute and relative), with implicit repeats ("l-2 6-6 2"). Arcs map to
/// Path.arcToPoint, whose clockwise flag matches SVG's sweep flag in y-down space.
Path parseSvgPath(String d) {
  final tokens = RegExp(r'[MmLlHhVvCcAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var cur = Offset.zero;
  var start = Offset.zero;

  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() {
    if (i >= tokens.length || isCommand(tokens[i])) {
      throw FormatException('missing number at token $i in "$d"');
    }
    return double.parse(tokens[i++]);
  }

  while (i < tokens.length) {
    if (isCommand(tokens[i])) {
      cmd = tokens[i++];
    } else if (cmd == 'Z' || cmd == 'z' || cmd.isEmpty) {
      throw FormatException('number without a command at token $i in "$d"');
    } else if (cmd == 'M') {
      cmd = 'L'; // numbers after a moveto are implicit linetos
    } else if (cmd == 'm') {
      cmd = 'l';
    }
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final p = Offset(next(), next());
        cur = rel ? cur + p : p;
        start = cur;
        path.moveTo(cur.dx, cur.dy);
      case 'L':
        final p = Offset(next(), next());
        cur = rel ? cur + p : p;
        path.lineTo(cur.dx, cur.dy);
      case 'H':
        final x = next();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
      case 'V':
        final y = next();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        path.lineTo(cur.dx, cur.dy);
      case 'C':
        final c1 = Offset(next(), next()), c2 = Offset(next(), next()), p = Offset(next(), next());
        final o = rel ? cur : Offset.zero;
        path.cubicTo(o.dx + c1.dx, o.dy + c1.dy, o.dx + c2.dx, o.dy + c2.dy, o.dx + p.dx, o.dy + p.dy);
        cur = o + p;
      case 'A':
        final rx = next(), ry = next(), rotation = next();
        final largeArc = next() != 0, sweep = next() != 0;
        final p = Offset(next(), next());
        cur = rel ? cur + p : p;
        path.arcToPoint(cur,
            radius: Radius.elliptical(rx, ry), rotation: rotation, largeArc: largeArc, clockwise: sweep);
      case 'Z':
        path.close();
        cur = start;
      default:
        throw FormatException('unsupported SVG path command "$cmd"');
    }
  }
  return path;
}
