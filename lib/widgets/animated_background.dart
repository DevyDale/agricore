import 'dart:math';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AnimatedBackground extends StatefulWidget {
  final Widget child;
  const AnimatedBackground({super.key, required this.child});
  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final r = Random(7);
    _particles = List.generate(
      44,
      (_) => _Particle(Offset(r.nextDouble(), r.nextDouble()),
          r.nextDouble() * 2.2 + 1.4, r.nextDouble()),
    );
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.bgGradient),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) =>
                  CustomPaint(painter: _ParticlePainter(_particles, _c.value)),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _Particle {
  final Offset pos;
  final double size;
  final double phase;
  _Particle(this.pos, this.size, this.phase);
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> ps;
  final double t;
  _ParticlePainter(this.ps, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in ps) {
      final tw = sin((t + p.phase) * 2 * pi) * 0.5 + 0.5;
      final paint = Paint()
        ..color = AppColors.emerald.withValues(alpha: 0.12 + tw * 0.32);
      canvas.drawCircle(Offset(p.pos.dx * size.width, p.pos.dy * size.height),
          p.size * (0.6 + tw * 0.6), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.t != t;
}
