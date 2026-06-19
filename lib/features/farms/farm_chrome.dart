import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/farmland_background.dart';

const Color _heroDark = Color(0xFF22432C);

/// Shared farmland hero app bar for farm sub-management screens.
class FarmHeroBar extends StatelessWidget {
  final String title;
  final String subtitle;
  const FarmHeroBar({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 176,
      backgroundColor: _heroDark,
      foregroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 16),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
        background: Stack(
          fit: StackFit.expand,
          children: [
            FarmlandBackground(showPins: false, child: const SizedBox.expand()),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC0E2018), Color(0x800E2018)]),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 50,
              child: SafeArea(
                bottom: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2))),
                  child: Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFBBF7D0))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient-icon stat tile with a count-up value.
class FarmStat extends StatelessWidget {
  final IconData icon;
  final double value;
  final String label;
  final int decimals;
  final String suffix;
  final Color c1, c2;
  const FarmStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.decimals = 0,
    this.suffix = '',
    required this.c1,
    required this.c2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 8))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 850),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              (decimals > 0 ? v.toStringAsFixed(decimals) : v.round().toString()) + suffix,
              style: const TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w900, fontSize: 22, color: AppColors.inkWarm),
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate500)),
        ],
      ),
    );
  }
}

/// Staggered fade + rise entrance, delayed by [index].
class FarmRise extends StatefulWidget {
  final int index;
  final Widget child;
  const FarmRise({super.key, required this.index, required this.child});
  @override
  State<FarmRise> createState() => _FarmRiseState();
}

class _FarmRiseState extends State<FarmRise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: (widget.index.clamp(0, 8)) * 55), () {
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
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, (1 - _a.value) * 14), child: child),
      ),
      child: widget.child,
    );
  }
}
