import 'package:flutter/material.dart';

/// A subtle fade + slide-up entrance animation. Pass [index] to stagger items
/// in a list or grid so they cascade in.
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final double offsetY;
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 420),
    this.offsetY = 16,
  });

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    final delayMs = (widget.index.clamp(0, 12)) * 45;
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * widget.offsetY), child: child),
        );
      },
    );
  }
}
