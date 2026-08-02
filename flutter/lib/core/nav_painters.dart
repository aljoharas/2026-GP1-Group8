/// The bottom-nav icons, drawn rather than shipped as assets.
///
/// The older screens each carry a private copy of these. New screens share
/// this one so a nav icon only has to be tweaked in a single place.
library;

import 'package:flutter/material.dart';

const _kText = Color(0xFFF0F0F0);
const _kMuted = Color(0xFF6B6B80);

Paint _navPaint(bool active) => Paint()
  ..color = active ? _kText : _kMuted
  ..strokeWidth = 2.0
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke;

class NavHomePainter extends CustomPainter {
  final bool active;
  const NavHomePainter(this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final path = Path()
      ..moveTo(3 * s, 9 * s)
      ..lineTo(12 * s, 2 * s)
      ..lineTo(21 * s, 9 * s)
      ..lineTo(21 * s, 20 * s)
      ..arcToPoint(Offset(19 * s, 22 * s), radius: Radius.circular(2 * s))
      ..lineTo(5 * s, 22 * s)
      ..arcToPoint(Offset(3 * s, 20 * s), radius: Radius.circular(2 * s))
      ..close();
    canvas.drawPath(path, _navPaint(active));
  }

  @override
  bool shouldRepaint(NavHomePainter o) => o.active != active;
}

class NavSearchPainter extends CustomPainter {
  final bool active;
  const NavSearchPainter(this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    canvas.drawCircle(Offset(11 * s, 11 * s), 8 * s, p);
    canvas.drawLine(Offset(16.65 * s, 16.65 * s), Offset(21 * s, 21 * s), p);
  }

  @override
  bool shouldRepaint(NavSearchPainter o) => o.active != active;
}

class NavFriendsPainter extends CustomPainter {
  final bool active;
  const NavFriendsPainter(this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    final body = Path()
      ..moveTo(17 * s, 21 * s)
      ..lineTo(17 * s, 19 * s)
      ..arcToPoint(Offset(13 * s, 15 * s),
          radius: Radius.circular(4 * s), clockwise: false)
      ..lineTo(5 * s, 15 * s)
      ..arcToPoint(Offset(1 * s, 19 * s),
          radius: Radius.circular(4 * s), clockwise: false)
      ..lineTo(1 * s, 21 * s);
    canvas.drawPath(body, p);
    canvas.drawCircle(Offset(9 * s, 7 * s), 4 * s, p);

    final body2 = Path()
      ..moveTo(23 * s, 21 * s)
      ..lineTo(23 * s, 19 * s)
      ..arcToPoint(Offset(20 * s, 15.13 * s),
          radius: Radius.circular(4 * s), clockwise: false);
    canvas.drawPath(body2, p);

    final head2 = Path()
      ..moveTo(16 * s, 3.13 * s)
      ..arcToPoint(Offset(16 * s, 10.88 * s), radius: Radius.circular(4 * s));
    canvas.drawPath(head2, p);
  }

  @override
  bool shouldRepaint(NavFriendsPainter o) => o.active != active;
}

class NavProfilePainter extends CustomPainter {
  final bool active;
  const NavProfilePainter(this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = _navPaint(active);
    final body = Path()
      ..moveTo(20 * s, 21 * s)
      ..lineTo(20 * s, 19 * s)
      ..arcToPoint(Offset(16 * s, 15 * s),
          radius: Radius.circular(4 * s), clockwise: false)
      ..lineTo(8 * s, 15 * s)
      ..arcToPoint(Offset(4 * s, 19 * s),
          radius: Radius.circular(4 * s), clockwise: false)
      ..lineTo(4 * s, 21 * s);
    canvas.drawPath(body, p);
    canvas.drawCircle(Offset(12 * s, 7 * s), 4 * s, p);
  }

  @override
  bool shouldRepaint(NavProfilePainter o) => o.active != active;
}

class NavPlusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(Offset(cx, cy - 9), Offset(cx, cy + 9), paint);
    canvas.drawLine(Offset(cx - 9, cy), Offset(cx + 9, cy), paint);
  }

  @override
  bool shouldRepaint(NavPlusPainter o) => false;
}
