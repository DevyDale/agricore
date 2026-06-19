import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Orbitron gradient "Agricore Dynamics" wordmark + leaf badge, matching the
/// web brand header. Fonts are bundled, so this renders the same everywhere.
class BrandLogo extends StatelessWidget {
  final double iconSize;
  final bool showText;
  final double titleSize;
  final bool showSubtitle;
  const BrandLogo({
    super.key,
    this.iconSize = 92,
    this.showText = true,
    this.titleSize = 30,
    this.showSubtitle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            gradient: AppColors.gradient,
            borderRadius: BorderRadius.circular(iconSize * 0.3),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withValues(alpha: 0.45),
                blurRadius: 34,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Icon(Icons.eco_rounded,
              color: Colors.white, size: iconSize * 0.55),
        ),
        if (showText) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ShaderMask(
                shaderCallback: (b) => AppColors.gradient.createShader(b),
                child: Text(
                  'Agricore Dynamics',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Orbitron',
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                          color: AppColors.green.withValues(alpha: 0.45),
                          blurRadius: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showSubtitle) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'Revolutionizing agriculture with smart technology, seamless marketplaces, and AI-powered growth',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.forest,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
