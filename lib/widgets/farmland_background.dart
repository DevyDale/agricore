import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Recreates the web hero's generated patchwork farmland: a grid of jittered
/// quad "fields", each filled with a rotated stripe pattern from a weighted
/// palette, plus a warm sun glow, vignette, and pulsing location pins.
class FarmlandBackground extends StatelessWidget {
  final Widget child;
  final bool showPins;
  const FarmlandBackground({super.key, required this.child, this.showPins = true});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.heroBase),
        Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _FieldsPainter())),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.95, -0.95),
                  radius: 1.15,
                  colors: [Color(0x99FFE7A8), Color(0x33FFCD78), Color(0x00FFCD78)],
                  stops: [0.0, 0.4, 0.72],
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.1, -0.35),
                  radius: 1.25,
                  colors: [Color(0x00081609), Color(0xA8081609)],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
          ),
        ),
        if (showPins) ...const [
          _Pin(Alignment(-0.60, -0.16)),
          _Pin(Alignment(0.44, 0.20)),
          _Pin(Alignment(-0.04, -0.40)),
        ],
        child,
      ],
    );
  }
}

class _Pin extends StatefulWidget {
  final Alignment align;
  const _Pin(this.align);
  @override
  State<_Pin> createState() => _PinState();
}

class _PinState extends State<_Pin> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.align,
      child: SizedBox(
        width: 44,
        height: 44,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: 0.5 + t * 1.3,
                  child: Opacity(
                    opacity: (1 - t) * 0.8,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.white.withValues(alpha: 0.35), spreadRadius: 3),
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FieldsPainter extends CustomPainter {
  static const _pal = <List<Color>>[
    [Color(0xFF2F5A34), Color(0xFF27502C)],
    [Color(0xFF3C7A3C), Color(0xFF336A33)],
    [Color(0xFF4F8438), Color(0xFF447730)],
    [Color(0xFF6F8D3F), Color(0xFF637F37)],
    [Color(0xFF8A9A4E), Color(0xFF7C8C42)],
    [Color(0xFFC39A48), Color(0xFFB58B3C)],
    [Color(0xFFD3AB57), Color(0xFFC59B48)],
    [Color(0xFFB15A36), Color(0xFF9F4E2E)],
    [Color(0xFFCDB878), Color(0xFFBDA863)],
  ];
  static const _ang = <double>[0, 16, 90, 74, 16, 0, 90, 30, 16];
  static const _bag = <int>[0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(20260619);
    final cols = (size.width / 130).round().clamp(4, 8);
    final rows = (size.height / 130).round().clamp(4, 12);
    final cw = size.width / cols, ch = size.height / rows;
    final jx = cw * 0.32, jy = ch * 0.32;

    final pts = List.generate(rows + 1, (r) {
      return List.generate(cols + 1, (c) {
        final edge = r == 0 || r == rows || c == 0 || c == cols;
        final x = c * cw + (edge ? 0 : (rnd.nextDouble() * 2 - 1) * jx);
        final y = r * ch + (edge ? 0 : (rnd.nextDouble() * 2 - 1) * jy);
        return Offset(x, y);
      });
    });

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x2B160F07)
      ..strokeWidth = 1.3;
    final reach = (cw + ch) * 1.5;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final a = pts[r][c], b = pts[r][c + 1], d = pts[r + 1][c + 1], e = pts[r + 1][c];
        final fi = _bag[rnd.nextInt(_bag.length)];
        final base = _pal[fi][0], stripe = _pal[fi][1];
        final poly = Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(d.dx, d.dy)
          ..lineTo(e.dx, e.dy)
          ..close();
        final cx = (a.dx + b.dx + d.dx + e.dx) / 4;
        final cy = (a.dy + b.dy + d.dy + e.dy) / 4;

        canvas.save();
        canvas.clipPath(poly);
        canvas.drawPaint(Paint()..color = base);
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(_ang[fi] * pi / 180);
        final sp = Paint()
          ..color = stripe
          ..strokeWidth = 3.6;
        for (double y = -reach; y < reach; y += 10) {
          canvas.drawLine(Offset(-reach, y), Offset(reach, y), sp);
        }
        canvas.restore();
        canvas.restore();
        canvas.drawPath(poly, border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FieldsPainter oldDelegate) => false;
}
