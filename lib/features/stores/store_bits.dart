import 'dart:convert';
import 'package:flutter/material.dart';

const Color kStallGreen = Color(0xFF0C6B46);
const Color kStallCream = Color(0xFFF4ECD9);
const Color kStallGold = Color(0xFFC39A48);

String _grp(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  final len = s.length;
  for (int i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String storeValue(num? n) => '\$${_grp(n ?? 0)}';

/// Robustly normalise countries_of_operation: array, char-by-char array,
/// JSON string, or comma string — all become a clean list.
List<String> normCountries(dynamic c) {
  if (c == null) return [];
  if (c is List) {
    if (c.isNotEmpty && c.every((x) => x is String && x.length <= 1)) {
      return c.join('').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return c.map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList();
  }
  if (c is String) {
    final t = c.trim();
    if (t.isEmpty) return [];
    if (t.startsWith('[')) {
      try {
        final p = jsonDecode(t);
        if (p is List) return p.map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList();
      } catch (_) {/* not valid JSON; fall back to treating it as a single value */}
      return [t];
    }
    if (t.contains(',')) return t.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    return [t];
  }
  return [];
}

// ---- striped awning + scalloped edge + verification stamp ----
class StallAwning extends StatelessWidget {
  final bool verified;
  const StallAwning({super.key, required this.verified});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: const [
                Expanded(child: SizedBox(width: double.infinity, child: CustomPaint(painter: _AwningPainter()))),
                SizedBox(height: 14, width: double.infinity, child: CustomPaint(painter: _ScallopPainter())),
              ],
            ),
          ),
          Positioned(top: 10, right: 10, child: _Stamp(verified: verified)),
        ],
      ),
    );
  }
}

class _AwningPainter extends CustomPainter {
  const _AwningPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const stripe = 22.0;
    final p = Paint();
    int i = 0;
    for (double x = 0; x < size.width; x += stripe) {
      p.color = (i % 2 == 0) ? kStallGreen : kStallCream;
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, size.height), p);
      i++;
    }
    p.color = Colors.white.withValues(alpha: 0.18);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 7), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _ScallopPainter extends CustomPainter {
  const _ScallopPainter();
  @override
  void paint(Canvas canvas, Size size) {
    const r = 11.0;
    const step = 22.0;
    final p = Paint()..style = PaintingStyle.fill;
    for (double cx = 11; cx - r < size.width; cx += step) {
      p.color = (((cx / step).floor()) % 2 == 0) ? kStallGreen : kStallCream;
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, 0), radius: r), 0, 3.14159, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Stamp extends StatelessWidget {
  final bool verified;
  const _Stamp({required this.verified});
  @override
  Widget build(BuildContext context) {
    final bg = verified ? const Color(0xFFECFDF3) : const Color(0xFFFFF7E6);
    final fg = verified ? const Color(0xFF166534) : const Color(0xFF92400E);
    final br = verified ? const Color(0xFF86EFAC) : const Color(0xFFFCD9A0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999), border: Border.all(color: br)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (verified) ...[
            Icon(Icons.verified_rounded, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(verified ? 'VERIFIED' : 'PENDING',
              style: TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: fg)),
        ],
      ),
    );
  }
}

class StallAvatar extends StatelessWidget {
  final double size;
  const StallAvatar({super.key, this.size = 42});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kStallGreen, Color(0xFF065F3C)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(Icons.storefront_rounded, color: Colors.white, size: size * 0.5),
    );
  }
}
